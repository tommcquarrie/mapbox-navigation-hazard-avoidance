/**
     # NHVR Hack Day Project: Restricted Access Avoidance
     
     Goals in priority order
     ✅ Store a static list of max-height obstacles
     ✅ Calculate a route which avoids those obstacles (static start and destination)
     ✅ Enable displaying the route on a map
     ✅ Recalculate route on tap of map, continue avoiding obstacles
     ✅ Display the restricted assets on the map
     ✅ Enable navigating on selected route
     ✅ Enable selecting alternative route
     ✅ Display the obstacles on the map during navigation
     [ ] Alert if the user is approaching a restricted asset, via digital horizon
     [ ] Enable toggle of route avoidance to demonstrate collision (Could hack this for demo)
     
     [ ] Tap on an asset to view the reasons for avoidance. Height/width/weight etc

     [ ] Filter the obstacles based on an input vehicle height (or at least fake it)
     [ ] Fetch obstacles from our API
     [ ] Fetch the route via our API
     [ ] Recalculate the route when deviating, while continuing to avoid obstacles (difficult to simulate)
     [ ] Customer feedback UI
     
     Please note: You may be saying to yourself "this code is terrible. It's like they've never written swift before". You would be right, I haven't.  This code should be thorougly reviewed and re-written by someone far more knowledgeable than myself before it went near real users.
      Things we may consider doing:
     [ ] Currently when you exit navigation there's a bunch of background processes/requests that keep running.  Need to work out how to terminate everything and clean up properly to avoid memory leaks
     [ ] Split this up into multiple components
     [ ] Drastically improve handling of errors and edge cases
     [ ] User's location is not currently in sync between the map view and the navigation view
 */

import UIKit
import MapKit
import MapboxMaps
import MapboxDirections
import MapboxCoreNavigation
import MapboxNavigation
import Turf

enum AlertLevel {
    case none
    case warning
    case danger
    case death
}

class NhvrNavigatorViewController: UIViewController, NavigationMapViewDelegate, NavigationViewControllerDelegate {
    
    // # configurable input values
    // NOTE: if the origin is different to the simulator's set gps location, that will cause the navigation simulator to reroute, which will lose
    // hazard avoidance. This is highly unsual given the location should be simulated.
    // longitude=144.9732180075918&latitude=-37.762789807397574
    var origin = CLLocationCoordinate2DMake(-37.762789807397574, 144.9732180075918)
    var destination = CLLocationCoordinate2DMake(-37.7779878, 144.9710791)
    var obstacleAvoidance: Bool = true
    
    // voice prompts
    let PROMPT_HAZARD_ON_ROUTE = SpokenInstruction(distanceAlongStep: 0, text: "Hazard on route, proceed with caution", ssmlText: "Hazard on route")
    let PROMPT_HAZARD_AHEAD = SpokenInstruction(distanceAlongStep: 0, text: "Hazard, ahead. Hazard, ahead. Hazard, ahead.", ssmlText: "Hazard head")
    let PROMPT_HAZARD_DEAD = SpokenInstruction(distanceAlongStep: 0, text: "Sorry, you are now dead", ssmlText: "Hazard head")
    
    // obstacles to avoid
    var obstacle_map_circles: [CircleAnnotation] {
        return [
            makeCircle(point: CLLocationCoordinate2D(latitude: -37.76921612135003, longitude: 144.97224769222004)),
            makeCircle(point: CLLocationCoordinate2D(latitude: -37.77214126409389, longitude: 144.9668805295816)),
            makeCircle(point: CLLocationCoordinate2D(latitude: -37.76735145190283, longitude: 144.9802780675356))
        ]
    }
    
    private var alertLevel: AlertLevel = .none {
        didSet {
            updateAlert()
        }
    }
    
    private var alertMessage: String = "" {
        didSet {
            print ("### \(alertMessage)")
            updateAlert()
        }
    }
                
    private func updateAlert () {

    }
    
    // obstacle detection calibration constants
    private let OBSTACLE_ALERT_DISTANCE:LocationDistance = 200
    private let OBSTACLE_DEATH_DISTANCE:LocationDistance = 15
    private let ROAD_WIDTH_TOLERANCE:LocationDistance = 20

    var navigationMapView: NavigationMapView!
    var navigationViewController: NavigationViewController!
    var navigationService: NavigationService!
    
    private let startButton: UIButton! = UIButton()
    private let upcomingIntersectionLabel = UILabel()
    private let alertLabel = UILabel()
    private let passiveLocationManager = PassiveLocationManager()
    private lazy var passiveLocationProvider = PassiveLocationProvider(locationManager: passiveLocationManager)
    
    private var totalDistance: CLLocationDistance = 0.0
    
    var routeOptions: RouteOptions!
    
    var currentRouteIndex = 0 {
        didSet {
            showCurrentRoute()
        }
    }
    
    var currentRoute: Route? {
        return routes?[currentRouteIndex]
    }
    
    var routes: [Route]? {
        return routeResponse?.routes
    }
    
    var routeResponse: RouteResponse! {
        didSet {
            guard currentRoute != nil else {
                navigationMapView.removeRoutes()
                return
            }
            currentRouteIndex = 0
        }
    }
    
    func showCurrentRoute() {
        guard let currentRoute = currentRoute else { return }
        
        var routes = [currentRoute]
        routes.append(contentsOf: self.routes!.filter {
            $0 != currentRoute
        })
        navigationMapView.showcase(routes)
    }
    
    
    var beginAnnotation: PointAnnotation?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupNavigationMapView()
        setupstartButton()
        requestRoute()
    }
    
    func makeRouteOptions() {
        if (obstacleAvoidance) {
            let exclude: URLQueryItem = URLQueryItem(name: "excludes", value: "point(144.97224769222004 -37.76921612135003),point(144.9668805295816 -37.77214126409389),point(144.9802780675356 -37.76735145190283)")
            routeOptions = NavigationRouteOptions(coordinates: [origin, destination], profileIdentifier: .automobile, queryItems: [exclude])
        } else {
            routeOptions = NavigationRouteOptions(coordinates: [origin, destination], profileIdentifier: .automobile)
        }
    }
    
    func setupNavigationMapView() {
        navigationMapView = NavigationMapView(frame: view.bounds)
        navigationMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        navigationMapView.delegate = self
        // Configure how map displays the user's location
        navigationMapView.userLocationStyle = .puck2D()
        
        let annotationsManager = navigationMapView.mapView.annotations.makeCircleAnnotationManager()
        annotationsManager.annotations = obstacle_map_circles
        
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        navigationMapView.addGestureRecognizer(longPressGestureRecognizer)
        
        view.addSubview(navigationMapView)
    }
    
    func setupElectronicHorizonUpdates() {
        // Customize the `ElectronicHorizonOptions` for `PassiveLocationManager` to start Electronic Horizon updates.
        let options = ElectronicHorizonOptions(length: 500, expansionLevel: 1, branchLength: 50, minTimeDeltaBetweenUpdates: nil)
        passiveLocationManager.startUpdatingElectronicHorizon(with: options)
        subscribeToElectronicHorizonUpdates()
    }
    
    private func subscribeToElectronicHorizonUpdates() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didUpdateElectronicHorizonPosition),
                                               name: .electronicHorizonDidUpdatePosition,
                                               object: nil)
    }

    @objc private func didUpdateElectronicHorizonPosition(_ notification: Notification) {
        let horizonTreeKey = RoadGraph.NotificationUserInfoKey.treeKey
        guard let horizonTree = notification.userInfo?[horizonTreeKey] as? RoadGraph.Edge else {
            return
        }
        
        obstacleAhead(from: horizonTree, roadGraph: passiveLocationManager.roadGraph)
    }
    
    func requestRoute() {
        makeRouteOptions()
        Directions.shared.calculate(routeOptions) { [weak self] (_, result) in
            switch result {
                case .failure(let error):
                    print(error.localizedDescription)
                case .success(let response):
                guard let strongSelf = self else {return}
                strongSelf.routeResponse = response
                strongSelf.navigationMapView.showcase(strongSelf.routes!)
                strongSelf.navigationMapView.showWaypoints(on: strongSelf.currentRoute!)
            }
        }
    }
    
    @objc func startButtonPressed(_ sender: UIButton) {
        navigate()
    }
    
    private func navigate() {
            let indexedRouteResponse = IndexedRouteResponse(routeResponse: routeResponse, routeIndex: currentRouteIndex)
            navigationService = MapboxNavigationService(
                indexedRouteResponse: indexedRouteResponse,
                // TODO: Currently there's a bug where, if during navigation it reroutes,
                //  it's not using our custom call and so it loses the obstacle avoidance. Need to fix this!! Might need to pass a different routing provider which is shared between the map and the navigationViewController
                customRoutingProvider: NavigationSettings.shared.directions,
                credentials: NavigationSettings.shared.directions.credentials,
                simulating: simulationIsEnabled ? .always : .onPoorGPS
            )
             
            let navigationOptions = NavigationOptions(navigationService: navigationService)
            navigationViewController = NavigationViewController(
                for: indexedRouteResponse,
                navigationOptions: navigationOptions
            )
            navigationViewController.modalPresentationStyle = .overFullScreen
             
            // Modify default `NavigationViewportDataSource` and `NavigationCameraStateTransition` to change
            // `NavigationCamera` behavior during active guidance.
            if let mapView = navigationViewController.navigationMapView?.mapView {
                let annotationsManager2 = mapView.annotations.makeCircleAnnotationManager()
                annotationsManager2.annotations = obstacle_map_circles
            }
             
        navigationMapView = navigationViewController.navigationMapView
            present(navigationViewController, animated: true, completion: nil)
            setupElectronicHorizonUpdates()
    }
    
    func setupstartButton() {
        startButton.setTitle("Start Navigation", for: .normal)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.backgroundColor = .lightGray
        startButton.setTitleColor(.darkGray, for: .highlighted)
        startButton.setTitleColor(.white, for: .normal)
//        startButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        startButton.addTarget(self, action: #selector(startButtonPressed(_:)), for: .touchUpInside)
        startButton.isHidden = false
        view.addSubview(startButton)
        startButton.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -20).isActive = true
        startButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        view.setNeedsLayout()
    }
    
    // Enable selecting an alternate route
    func navigationMapView(_ mapView: NavigationMapView, didSelect route: Route) {
        self.currentRouteIndex = self.routes?.firstIndex(of: route) ?? 0
    }
    
    // navigate to the pressed location on long press
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .ended else { return }
      destination = navigationMapView.mapView.mapboxMap.coordinate(for: gesture.location(in: navigationMapView.mapView))
        
        requestRoute()
    }
    
    func makeCircle(point:CLLocationCoordinate2D) -> CircleAnnotation {
        var circle = CircleAnnotation(centerCoordinate:point)
        circle.circleColor = StyleColor(.red)
        circle.circleRadius = 10
        return circle
    }
    
    private func pointIsOnRoad(coordinates: [LocationCoordinate2D], to: LocationCoordinate2D) -> Bool {
        
        // NOTE: This calculation is not sufficient.  What this is doing is taking a line consisting of multiple points, finding the closest point on the line to the subject, and checking if that distance is within the threshold.  This doesn't work if the subject is on the line but it's a long line. Ideally what we would do is expand the line to a polygon, using something like turf.js' buffer, but unfortunately the swift port of turf doesn't include this feature.
        // we could also try to algorithmically work out if the point is on the line, but that requires math that's far beyond my tiny frontend brain.
        
        let line = LineString( coordinates )
        let closestCoordinate = line.closestCoordinate(to: to)
        return to.distance(to: closestCoordinate!.coordinate) < ROAD_WIDTH_TOLERANCE;
    }
    
    private func obstacleAhead(from horizon: RoadGraph.Edge, roadGraph: RoadGraph) {
        
        guard let userLocation =
                navigationService.locationManager.location else { return }
            
        let currentLocation = CLLocation(latitude: userLocation.coordinate.latitude,
                              longitude: userLocation.coordinate.longitude)
        
        let mostProbableEdge = horizon.outletEdges.max(by: { $0.probability < $1.probability })
        for edge in horizon.outletEdges {
            if let shape = roadGraph.edgeShape(edgeIdentifier: edge.identifier) {
                if edge.identifier != mostProbableEdge?.identifier {
                    for obstacle in obstacle_map_circles {
                        let obstacleIsOnRoad = pointIsOnRoad(coordinates: shape.coordinates, to: obstacle.point.coordinates)
                        
                        if (obstacleIsOnRoad) {
                            let edgeData = roadGraph.edgeMetadata(edgeIdentifier: edge.identifier)
                            switch(edgeData?.drivingSide) {
                                case .left:
                                    alertMessage = "Obstacle on your left"
                                    alertLevel = .warning
                                    break
                                    
                                case .right:
                                    alertMessage = "Obstacle on your right"
                                    alertLevel = .warning
                                default:
                                    alertMessage = ""
                            }
                        }
                    }
                }
            }
        }
        
        let mostProbableRoadLine = routeLine(from: horizon, roadGraph: roadGraph);
        
        for obstacle in obstacle_map_circles {
            let obstacleIsOnRoad = pointIsOnRoad(coordinates: mostProbableRoadLine, to: obstacle.point.coordinates)
            
            // check if the obstacle is touching the road (which is a vector)
            if (obstacleIsOnRoad) {
                // TODO: also check the distance between the obstacle and the vehicle
                // TODO: need a way to queue/throttle the speech instructions
                let obstacleDistanceFromVehicle = obstacle.point.coordinates.distance(to: currentLocation.coordinate)
                let instruction = SpokenInstruction(distanceAlongStep: 0, text: "Hazard ahead, proceed with caution", ssmlText: "Hazard on route")
                let leg = navigationService.routeProgress.currentLegProgress
//                        navigationViewController.voiceController.speechSynthesizer.speak(instruction, during: leg, locale: Locale(identifier: "en_AU"))
                if (obstacleDistanceFromVehicle < OBSTACLE_DEATH_DISTANCE) {
                    print("You are now dead ☠️")
                    navigationViewController.voiceController.speechSynthesizer.speak(PROMPT_HAZARD_DEAD, during: leg, locale: Locale(identifier: "en_AU"))
                    alertMessage = "You are now dead"
                    alertLevel = .death
                    navigationService.stop()
                    return
                }
                else if (obstacleDistanceFromVehicle < OBSTACLE_ALERT_DISTANCE) {
                    print ("### OBSTACLE AHEAD!!! \(obstacleDistanceFromVehicle)")
                    alertMessage = "Obstacle ahead in \(obstacleDistanceFromVehicle) meters"
                    alertLevel = .danger
                    return
                }
                else {
                    alertMessage = "Obstacle ahead in \(obstacleDistanceFromVehicle) meters"
                    alertLevel = .warning
                }
            }
        }
    }

    private func routeLine(from edge: RoadGraph.Edge, roadGraph: RoadGraph) -> [LocationCoordinate2D] {
        var coordinates = [LocationCoordinate2D]()
        var edge: RoadGraph.Edge? = edge

        // Update the route line shape and total distance of the most probable path.
        while let currentEdge = edge {
            if let shape = roadGraph.edgeShape(edgeIdentifier: currentEdge.identifier) {
                coordinates.append(contentsOf: shape.coordinates.dropFirst(coordinates.isEmpty ? 0 : 1))
            }
            edge = currentEdge.outletEdges.max(by: { $0.probability < $1.probability })
        }
        return coordinates
    }
    
    // Override layout lifecycle callback to be able to style the start button.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        startButton.layer.cornerRadius = startButton.bounds.midY
        startButton.clipsToBounds = true
        startButton.setNeedsDisplay()
    }
}


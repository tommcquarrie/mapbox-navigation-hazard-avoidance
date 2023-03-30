/**
NHVR Hack Day Project: Restricted Access Avoidance
 
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
 [ ] Split this up into multiple components
 [ ] Drastically improve handling of errors and edge cases
 [ ] User's location is not currently in sync between the map view and the navigation view
 */

import UIKit
import MapboxMaps
import MapboxDirections
import MapboxCoreNavigation
import MapboxNavigation
import Turf

class BasicViewController: UIViewController, NavigationMapViewDelegate, NavigationViewControllerDelegate {

    var navigationMapView: NavigationMapView!
    var navigationViewController: NavigationViewController!
    var navigationService: NavigationService!
    var startButton: UIButton!
    var origin = CLLocationCoordinate2DMake(-37.7620033, 144.9733776)
    var destination = CLLocationCoordinate2DMake(-37.7779878, 144.9710791)
    private let upcomingIntersectionLabel = UILabel()
    private let passiveLocationManager = PassiveLocationManager()
    private lazy var passiveLocationProvider = PassiveLocationProvider(locationManager: passiveLocationManager)
    private var totalDistance: CLLocationDistance = 0.0
    let OBSTACLE_ALERT_DISTANCE:LocationDistance = 200
    let OBSTACLE_DEATH_DISTANCE:LocationDistance = 15
    let ROAD_WIDTH_TOLERANCE:LocationDistance = 20
    
    // obstacles to avoid
    let obs1 = CLLocationCoordinate2D(latitude: -37.76921612135003, longitude: 144.97224769222004)
    let obs2 = CLLocationCoordinate2D(latitude: -37.77214126409389, longitude: 144.9668805295816)
    let obs3 = CLLocationCoordinate2D(latitude: -37.76735145190283, longitude: 144.9802780675356)

    var obstacle_map_circles: [CircleAnnotation] {
        return [
            makeCircle(point: obs1),
            makeCircle(point: obs3),
            makeCircle(point: obs2)
        ]
    }
    
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
        setupUpcomingIntersectionLabel()
        setupstartButton()
        requestRoute()
    }
    
    func makeRouteOptions() {
        // TEMPORARY COMMENT OUT, should use a toggle
//        let exclude: URLQueryItem = URLQueryItem(name: "excludes", value: "point(144.97224769222004 -37.76921612135003),point(144.9668805295816 -37.77214126409389),point(144.9802780675356 -37.76735145190283)")
//        routeOptions = NavigationRouteOptions(coordinates: [origin, destination], profileIdentifier: .automobile, queryItems: [exclude])
        routeOptions = NavigationRouteOptions(coordinates: [origin, destination], profileIdentifier: .automobile)
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
    
    private func setupUpcomingIntersectionLabel() {
        upcomingIntersectionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(upcomingIntersectionLabel)

        let safeAreaWidthAnchor = view.safeAreaLayoutGuide.widthAnchor
        NSLayoutConstraint.activate([
            upcomingIntersectionLabel.widthAnchor.constraint(lessThanOrEqualTo: safeAreaWidthAnchor, multiplier: 0.9),
            upcomingIntersectionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            upcomingIntersectionLabel.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor)
        ])
        upcomingIntersectionLabel.backgroundColor = #colorLiteral(red: 0.9568627477, green: 0.6588235497, blue: 0.5450980663, alpha: 1)
        upcomingIntersectionLabel.layer.cornerRadius = 5
        upcomingIntersectionLabel.numberOfLines = 0
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
        guard let horizonTree = notification.userInfo?[horizonTreeKey] as? RoadGraph.Edge,
              let position = notification.userInfo?[RoadGraph.NotificationUserInfoKey.positionKey] as? RoadGraph.Position,
              let updatesMostProbablePath = notification.userInfo?[RoadGraph.NotificationUserInfoKey.updatesMostProbablePathKey] as? Bool else {
            return
        }

        let currentStreetName = streetName(for: horizonTree)
        let upcomingCrossStreet = nearestCrossStreetName(from: horizonTree)
        updateLabel(currentStreetName: currentStreetName, predictedCrossStreet: upcomingCrossStreet)

        // Update the most probable path when the position update indicates a new most probable path (MPP).
        if updatesMostProbablePath {
//            print("updateMostProbablePath")
            let mostProbablePath = routeLine(from: horizonTree, roadGraph: passiveLocationManager.roadGraph)
            updateMostProbablePath(with: mostProbablePath)
        }

        // Update the most probable path layer when the position update indicates
        // a change of the fraction of the point traveled distance to the current edge’s length.
        updateMostProbablePathLayer(fractionFromStart: position.fractionFromStart,
                                    roadGraph: passiveLocationManager.roadGraph,
                                    currentEdge: horizonTree.identifier)
        
        let obstacleAheadVal = obstacleAhead(from: horizonTree, roadGraph: passiveLocationManager.roadGraph)
        if (obstacleAheadVal != nil) {
            upcomingIntersectionLabel.backgroundColor = .red
        }
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
                let customViewportDataSource = CustomViewportDataSource(mapView)
                navigationViewController.navigationMapView?.navigationCamera.viewportDataSource = customViewportDataSource
                 
                let customCameraStateTransition = CustomCameraStateTransition(mapView)
                navigationViewController.navigationMapView?.navigationCamera.cameraStateTransition = customCameraStateTransition
                
                let annotationsManager2 = mapView.annotations.makeCircleAnnotationManager()
                annotationsManager2.annotations = obstacle_map_circles
            }
             
            present(navigationViewController, animated: true, completion: nil)
            setupElectronicHorizonUpdates()
    }
    
    func setupstartButton() {
        startButton = UIButton()
        startButton.setTitle("Start Navigation", for: .normal)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.backgroundColor = .lightGray
        startButton.setTitleColor(.darkGray, for: .highlighted)
        startButton.setTitleColor(.white, for: .normal)
        startButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
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
    
    private func makeCircle(point:CLLocationCoordinate2D) -> CircleAnnotation {
        var circle = CircleAnnotation(centerCoordinate:point)
        circle.circleColor = StyleColor(.red)
        circle.circleRadius = 10
        return circle
    }

    private func streetName(for edge: RoadGraph.Edge) -> String? {
        let edgeMetadata = passiveLocationManager.roadGraph.edgeMetadata(edgeIdentifier: edge.identifier)
        return edgeMetadata?.names.first?.text
    }

    private func nearestCrossStreetName(from edge: RoadGraph.Edge) -> String? {
        let initialStreetName = streetName(for: edge)
        var currentEdge: RoadGraph.Edge? = edge
        while let nextEdge = currentEdge?.outletEdges.max(by: { $0.probability < $1.probability }) {
            if let nextStreetName = streetName(for: nextEdge), nextStreetName != initialStreetName {
                return nextStreetName
            }
            currentEdge = nextEdge
        }
        return nil
    }

    private func updateLabel(currentStreetName: String?, predictedCrossStreet: String?) {
        var statusString = ""
        if let currentStreetName = currentStreetName {
            statusString = "Currently on:\n\(currentStreetName)"
            if let predictedCrossStreet = predictedCrossStreet {
                statusString += "\nUpcoming intersection with:\n\(predictedCrossStreet)"
            } else {
                statusString += "\nNo upcoming intersections"
            }
        }

        DispatchQueue.main.async {
            self.upcomingIntersectionLabel.text = statusString
            self.upcomingIntersectionLabel.sizeToFit()
        }
    }
    
    private func distanceToClosestPoint(coordinates: [LocationCoordinate2D], to: LocationCoordinate2D) -> LocationDistance {
        let line = LineString( coordinates )
        let closestCoordinate = line.closestCoordinate(to: to)
        return to.distance(to: closestCoordinate!.coordinate);
    }
    
    private func obstacleAhead(from horizon: RoadGraph.Edge, roadGraph: RoadGraph) {
        var edge: RoadGraph.Edge? = horizon
        
        guard let userLocation =
                navigationService.locationManager.location else { return }
            
        let currentLocation = CLLocation(latitude: userLocation.coordinate.latitude,
                              longitude: userLocation.coordinate.longitude)

        while let currentEdge = edge {
            if let shape = roadGraph.edgeShape(edgeIdentifier: currentEdge.identifier) {
                
                for obstacle in [obs1, obs2, obs3] {
                    
                    let distance = distanceToClosestPoint(coordinates: shape.coordinates, to: obstacle)
                    
                    // check if the obstacle is touching the road (which is a vector)
                    if (distance < ROAD_WIDTH_TOLERANCE) {
                        // TODO: also check the distance between the obstacle and the vehicle
                        let obstacleDistanceFromVehicle = obstacle.distance(to: currentLocation.coordinate)
                        print ("### OBSTACLE on path!!! distance from path: \(distance), distance from vehicle: \(obstacleDistanceFromVehicle)")
                        if (obstacleDistanceFromVehicle < OBSTACLE_DEATH_DISTANCE) {
                            print("You are now dead ☠️")
                            navigationService.stop()
                            return
                        }
                        else if (obstacleDistanceFromVehicle < OBSTACLE_ALERT_DISTANCE) {
                            print ("### OBSTACLE AHEAD!!! \(obstacleDistanceFromVehicle)")
                            return
                        }
                    }
                }
            }
            
            // warning alert if there are hazards in proximity. if there is a branch with a hazard you don't want to turn onto that road.
            // if the obstacle touches a branch, and there are no other branches closer than the obstacle,
            //  then we must turn around.
            //
            // big red alert and audio alertwhen you are heading towards a hazard and must turn around
            edge = currentEdge.outletEdges.max(by: { $0.probability < $1.probability })
        }
    }

    private func routeLine(from edge: RoadGraph.Edge, roadGraph: RoadGraph) -> [LocationCoordinate2D] {
        var coordinates = [LocationCoordinate2D]()
        var edge: RoadGraph.Edge? = edge
        totalDistance = 0.0

        // Update the route line shape and total distance of the most probable path.
        while let currentEdge = edge {
            if let shape = roadGraph.edgeShape(edgeIdentifier: currentEdge.identifier) {
                coordinates.append(contentsOf: shape.coordinates.dropFirst(coordinates.isEmpty ? 0 : 1))
            }
            if let distance = roadGraph.edgeMetadata(edgeIdentifier: currentEdge.identifier)?.length {
                totalDistance += distance
            }
            edge = currentEdge.outletEdges.max(by: { $0.probability < $1.probability })
        }
        return coordinates
    }


    private func updateMostProbablePath(with mostProbablePath: [CLLocationCoordinate2D]) {
        let feature = Feature(geometry: .lineString(LineString(mostProbablePath)))
        
        try? navigationViewController!.navigationMapView!.mapView.mapboxMap.style.updateGeoJSONSource(withId: sourceIdentifier,
                                                                           geoJSON: .feature(feature))
    }

    private func updateMostProbablePathLayer(fractionFromStart: Double,
                                             roadGraph: RoadGraph,
                                             currentEdge: RoadGraph.Edge.Identifier) {
        // Based on the length of current edge and the total distance of the most probable path (MPP),
        // calculate the fraction of the point traveled distance to the whole most probable path (MPP).
        if totalDistance > 0.0,
           let currentLength = roadGraph.edgeMetadata(edgeIdentifier: currentEdge)?.length {
            let fraction = fractionFromStart * currentLength / totalDistance
            updateMostProbablePathLayerFraction(fraction)
        }
    }

    private let sourceIdentifier = "mpp-source"
    private let layerIdentifier = "mpp-layer"
    private let routeLineColor: UIColor = .green.withAlphaComponent(0.9)
    private let traversedRouteColor: UIColor = .red.withAlphaComponent(0.9)

    private func setupMostProbablePathStyle() {
        var source = GeoJSONSource()
        source.data = .geometry(Geometry.lineString(LineString([])))
        source.lineMetrics = true
        try? navigationViewController!.navigationMapView!.mapView.mapboxMap.style.addSource(source, id: sourceIdentifier)

        var layer = LineLayer(id: layerIdentifier)
        layer.source = sourceIdentifier
        layer.lineWidth = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                RouteLineWidthByZoomLevel.mapValues { $0 * 0.5 }
            }
        )
        layer.lineColor = .constant(.init(routeLineColor))
        layer.lineCap = .constant(.round)
        layer.lineJoin = .constant(.miter)
        layer.minZoom = 9
        try? navigationViewController!.navigationMapView!.mapView.mapboxMap.style.addLayer(layer)
    }

    // Update the line gradient property of the most probable path line layer,
    // so the part of the most probable path that has been traversed will be rendered with full transparency.
    private func updateMostProbablePathLayerFraction(_ fraction: Double) {
        let nextDown = max(fraction.nextDown, 0.0)
        let exp = Exp(.step) {
            Exp(.lineProgress)
            traversedRouteColor
            nextDown
            traversedRouteColor
            fraction
            routeLineColor
        }

        if let data = try? JSONEncoder().encode(exp.self),
           let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
            try? navigationViewController!.navigationMapView!.mapView.mapboxMap.style.setLayerProperty(for: layerIdentifier,
                                                                            property: "line-gradient",
                                                                            value: jsonObject)
        }
    }
    
    // Override layout lifecycle callback to be able to style the start button.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        startButton.layer.cornerRadius = startButton.bounds.midY
        startButton.clipsToBounds = true
        startButton.setNeedsDisplay()
    }
}

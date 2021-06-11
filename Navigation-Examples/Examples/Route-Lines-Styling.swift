import UIKit
import MapboxCoreNavigation
import MapboxNavigation
import MapboxDirections
import MapboxMaps
import Turf

class RouteLinesStylingViewController: UIViewController {
    
    var navigationMapView: NavigationMapView!
    
    var navigationRouteOptions: NavigationRouteOptions!
    
    var currentRoute: Route? {
        get {
            return routes?.first
        }
        set {
            guard let selected = newValue else { routes = nil; return }
            guard let routes = routes else { self.routes = [selected]; return }
            self.routes = [selected] + routes.filter { $0 != selected }
        }
    }
    
    var routes: [Route]? {
        didSet {
            guard let routes = routes, let currentRoute = routes.first else {
                navigationMapView.removeRoutes()
                navigationMapView.removeWaypoints()
                return
            }
            
            navigationMapView.show(routes)
            navigationMapView.showWaypoints(on: currentRoute)
        }
    }
    
    // MARK: - UIViewController lifecycle methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupNavigationMapView()
        setupPerformActionBarButtonItem()
        setupGestureRecognizers()
    }
    
    // MARK: - Setting-up methods
    
    func setupNavigationMapView() {
        navigationMapView = NavigationMapView(frame: view.bounds)
        navigationMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        navigationMapView.delegate = self
        navigationMapView.userLocationStyle = .puck2D()
        
        let navigationViewportDataSource = NavigationViewportDataSource(navigationMapView.mapView, viewportDataSourceType: .raw)
        navigationMapView.navigationCamera.viewportDataSource = navigationViewportDataSource
        
        view.addSubview(navigationMapView)
    }
    
    func setupPerformActionBarButtonItem() {
        let settingsBarButtonItem = UIBarButtonItem(title: NSString(string: "\u{2699}\u{0000FE0E}") as String,
                                                    style: .plain,
                                                    target: self,
                                                    action: #selector(performAction))
        settingsBarButtonItem.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 30)], for: .normal)
        settingsBarButtonItem.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 30)], for: .highlighted)
        navigationItem.rightBarButtonItem = settingsBarButtonItem
    }
    
    @objc func performAction(_ sender: Any) {
        let alertController = UIAlertController(title: "Perform action",
                                                message: "Select specific action to perform it", preferredStyle: .actionSheet)
        
        typealias ActionHandler = (UIAlertAction) -> Void
        
        let startNavigation: ActionHandler = { _ in self.startNavigation() }
        let removeRoutes: ActionHandler = { _ in self.routes = nil }
        
        let actions: [(String, UIAlertAction.Style, ActionHandler?)] = [
            ("Start Navigation", .default, startNavigation),
            ("Remove Routes", .default, removeRoutes),
            ("Cancel", .cancel, nil)
        ]
        
        actions
            .map({ payload in UIAlertAction(title: payload.0, style: payload.1, handler: payload.2) })
            .forEach(alertController.addAction(_:))
        
        if let popoverController = alertController.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(alertController, animated: true, completion: nil)
    }
    
    func setupGestureRecognizers() {
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        navigationMapView.addGestureRecognizer(longPressGestureRecognizer)
    }
    
    @objc func startNavigation() {
        guard let route = currentRoute else {
            print("Please select at least one destination coordinate to start navigation.")
            return
        }
        
        let navigationService = MapboxNavigationService(route: route,
                                                        routeIndex: 0,
                                                        routeOptions: navigationRouteOptions,
                                                        simulating: simulationIsEnabled ? .always : .onPoorGPS)
        
        let navigationOptions = NavigationOptions(navigationService: navigationService)
        let navigationViewController = NavigationViewController(for: route,
                                                                routeIndex: 0,
                                                                routeOptions: navigationRouteOptions,
                                                                navigationOptions: navigationOptions)
        navigationViewController.delegate = self
        navigationViewController.modalPresentationStyle = .fullScreen
        
        navigationViewController.routeLineTracksTraversal = true
        
        present(navigationViewController, animated: true, completion: nil)
    }
    
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        
        let mapView = navigationMapView.mapView
        let destinationCoordinate = mapView?.mapboxMap.coordinate(for: gesture.location(in: mapView))
        requestRoute(destinationCoordinate)
    }
    
    func requestRoute(_ destinationCoordinate: CLLocationCoordinate2D?) {
        guard let userLocation = navigationMapView.mapView.location.latestLocation?.internalLocation else {
            print("User location is not valid. Make sure to enable Location Services.")
            return
        }
        guard let destinationCoordinate = destinationCoordinate else { return }
        
        let waypoints = [
            Waypoint(coordinate: userLocation.coordinate),
            Waypoint(coordinate: destinationCoordinate)
        ]
        
        let navigationRouteOptions = NavigationRouteOptions(waypoints: waypoints)
        Directions.shared.calculate(navigationRouteOptions) { [weak self] (session, result) in
            switch result {
            case .failure(let error):
                NSLog("Error occured while requesting route: \(error.localizedDescription).")
            case .success(let response):
                guard let routes = response.routes else { return }
                self?.navigationRouteOptions = navigationRouteOptions
                self?.routes = routes
                self?.navigationMapView.show(routes)
                if let currentRoute = self?.currentRoute {
                    self?.navigationMapView.showWaypoints(on: currentRoute)
                }
            }
        }
    }
}

// MARK: - NavigationMapViewDelegate methods

extension RouteLinesStylingViewController: NavigationMapViewDelegate {
    
    func lineWidthExpression(_ multiplier: Double = 1.0) -> Expression {
        let lineWidthExpression = Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            // It's possible to change route line width depending on zoom level, by using expression
            // instead of constant. Navigation SDK for iOS also exposes `RouteLineWidthByZoomLevel`
            // public property, which contains default values for route lines on specific zoom levels.
            RouteLineWidthByZoomLevel.multiplied(by: multiplier)
        }
        
        return lineWidthExpression
    }
    
    func navigationMapView(_ mapView: NavigationMapView, didSelect route: Route) {
        currentRoute = route
    }
    
    // It's possible to change route line shape in preview mode by adding own implementation to either
    // `NavigationMapView.navigationMapView(_:shapeFor:)` or `NavigationMapView.navigationMapView(_:casingShapeFor:)`.
    func navigationMapView(_ navigationMapView: NavigationMapView, shapeFor route: Route) -> LineString? {
        return route.shape
    }
    
    func navigationMapView(_ navigationMapView: NavigationMapView, casingShapeFor route: Route) -> LineString? {
        return route.shape
    }
    
    func navigationMapView(_ navigationMapView: NavigationMapView, routeLineLayerWithIdentifier identifier: String, sourceIdentifier: String) -> LineLayer? {
        var lineLayer = LineLayer(id: identifier)
        lineLayer.source = sourceIdentifier
        
        // `identifier` parameter contains unique identifier of the route layer or its casing.
        // Such identifier consists of several parts: unique address of route object, whether route is
        // main or alternative, and whether route is casing or not. For example: identifier for
        // main route line will look like this: `0x0000600001168000.main.route_line`, and for
        // alternative route line casing will look like this: `0x0000600001ddee80.alternative.route_line_casing`.
        lineLayer.lineColor = .constant(.init(color: identifier.contains("main") ? #colorLiteral(red: 0.337254902, green: 0.6588235294, blue: 0.9843137255, alpha: 1) : #colorLiteral(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)))
        lineLayer.lineWidth = .expression(lineWidthExpression())
        lineLayer.lineJoin = .constant(.round)
        lineLayer.lineCap = .constant(.round)
        
        return lineLayer
    }
    
    func navigationMapView(_ navigationMapView: NavigationMapView, routeCasingLineLayerWithIdentifier identifier: String, sourceIdentifier: String) -> LineLayer? {
        var lineLayer = LineLayer(id: identifier)
        lineLayer.source = sourceIdentifier
        
        // Based on information stored in `identifier` property (whether route line is main or not)
        // route line will be colored differently.
        lineLayer.lineColor = .constant(.init(color: identifier.contains("main") ? #colorLiteral(red: 0.1843137255, green: 0.4784313725, blue: 0.7764705882, alpha: 1) : #colorLiteral(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)))
        lineLayer.lineWidth = .expression(lineWidthExpression(1.2))
        lineLayer.lineJoin = .constant(.round)
        lineLayer.lineCap = .constant(.round)
        
        return lineLayer
    }
}

// MARK: - NavigationViewControllerDelegate methods

extension RouteLinesStylingViewController: NavigationViewControllerDelegate {
    
    func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
        dismiss(animated: true, completion: nil)
    }
    
    // Similarly to preview mode, when using `NavigationMapView`, it's possible to change
    // route line styling during active guidance in `NavigationViewController`.
    func navigationViewController(_ navigationViewController: NavigationViewController, routeLineLayerWithIdentifier identifier: String, sourceIdentifier: String) -> LineLayer? {
        var lineLayer = LineLayer(id: identifier)
        lineLayer.source = sourceIdentifier
        lineLayer.lineColor = .constant(.init(color: identifier.contains("main") ? #colorLiteral(red: 0.337254902, green: 0.6588235294, blue: 0.9843137255, alpha: 1) : #colorLiteral(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)))
        lineLayer.lineWidth = .expression(lineWidthExpression())
        lineLayer.lineJoin = .constant(.round)
        lineLayer.lineCap = .constant(.round)
        
        return lineLayer
    }
    
    func navigationViewController(_ navigationViewController: NavigationViewController, routeCasingLineLayerWithIdentifier identifier: String, sourceIdentifier: String) -> LineLayer? {
        var lineLayer = LineLayer(id: identifier)
        lineLayer.source = sourceIdentifier
        lineLayer.lineColor = .constant(.init(color: identifier.contains("main") ? #colorLiteral(red: 0.1843137255, green: 0.4784313725, blue: 0.7764705882, alpha: 1) : #colorLiteral(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)))
        lineLayer.lineWidth = .expression(lineWidthExpression(1.2))
        lineLayer.lineJoin = .constant(.round)
        lineLayer.lineCap = .constant(.round)
        
        return lineLayer
    }
}

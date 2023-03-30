//
//  NHVR-HazardAvoidance.swift
//  Navigation-Examples
//
//  Created by Tom McQuarrie on 24/3/2023.
//  Copyright © 2023 Mapbox. All rights reserved.
//

import UIKit
import MapboxMaps
import MapboxDirections
import MapboxCoreNavigation
import MapboxNavigation
import Turf


class NhvrHazardAlertViewController: NhvrNavigatorViewController {
    override var obstacleAvoidance: Bool {
        get {
            return false
        }
        set {
            
        }
    }
    
    override var obstacle_map_circles: [CircleAnnotation] {
        return [
            makeCircle(point: CLLocationCoordinate2D(latitude: -37.764596444366376, longitude: 144.97331472557335)),
            makeCircle(point: CLLocationCoordinate2D(latitude: -37.76921612135003, longitude: 144.97224769222004)),
            makeCircle(point: CLLocationCoordinate2D(latitude: -37.77214126409389, longitude: 144.9668805295816)),
            makeCircle(point: CLLocationCoordinate2D(latitude: -37.76735145190283, longitude: 144.9802780675356))
        ]
    }
    
    // longitude=144.97331472557335&latitude=-37.764596444366376
//    let obs2 = CLLocationCoordinate2D(latitude: -37.77214126409389, longitude: 144.9668805295816)
//    let obs3 = CLLocationCoordinate2D(latitude: -37.76735145190283, longitude: 144.9802780675356)
}

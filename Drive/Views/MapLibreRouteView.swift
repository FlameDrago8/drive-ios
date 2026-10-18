import SwiftUI
import CoreLocation
import MapLibre

// MARK: – Telemetry Map Configuration
/// Single point of configuration for the vector basemap. MapLibre renders the
/// route on top of whatever style these URLs point at; supply a hosted vector
/// style and real roads appear under the electric line — in both light and dark.
enum TelemetryMap {
    /// Optional MapTiler key. Leave empty to use OpenFreeMap's free, keyless
    /// basemap (no signup, no request limits, commercial use allowed). Paste a
    /// MapTiler key only if you'd rather use their styles:
    /// https://cloud.maptiler.com/account/keys/
    static let apiKey = ""

    /// MapTiler style IDs (only used when `apiKey` is set).
    private static let darkStyleID  = "streets-v2-dark"
    private static let lightStyleID = "streets-v2"

    /// Keyless OpenFreeMap vector styles — real roads under the route, in both
    /// appearances, no API key required. Attribution ("OpenFreeMap © OpenMapTiles,
    /// Data from OpenStreetMap") is added automatically by MapLibre.
    private static let darkFreeStyle  = "https://tiles.openfreemap.org/styles/dark"
    private static let lightFreeStyle = "https://tiles.openfreemap.org/styles/positron"

    /// The style URL to load for the current appearance.
    static func styleURL(for scheme: ColorScheme) -> URL {
        if !apiKey.isEmpty {
            let id = scheme == .dark ? darkStyleID : lightStyleID
            return URL(string: "https://api.maptiler.com/maps/\(id)/style.json?key=\(apiKey)")!
        }
        let free = scheme == .dark ? darkFreeStyle : lightFreeStyle
        return URL(string: free)!
    }
}

// MARK: – MapLibre Route Representable
/// Non-interactive vector map that draws a single drive as our electric line,
/// badged like an instrument readout. Real roads come from the configured vector
/// basemap; the route, glow, markers and styling are ours. Adapts to light/dark.
struct MapLibreRouteRepresentable: UIViewRepresentable {
    let route: [RoutePoint]
    let colorScheme: ColorScheme

    private var coords: [CLLocationCoordinate2D] {
        route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(coords: coords, scheme: colorScheme) }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: TelemetryMap.styleURL(for: colorScheme))
        mapView.delegate = context.coordinator
        mapView.backgroundColor = UIColor(DS.Colors.bgCard)

        // Read-only instrument display — no gestures.
        mapView.allowsScrolling = false
        mapView.allowsZooming = false
        mapView.allowsRotating = false
        mapView.allowsTilting = false
        mapView.compassView.isHidden = true
        mapView.showsUserLocation = false

        // OSM/provider attribution stays visible for license compliance, tucked
        // into the corner so it doesn't fight the readout.
        mapView.attributionButtonPosition = .bottomRight
        mapView.logoView.isHidden = true

        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.coords = coords
        // Reload the basemap when the system appearance flips — didFinishLoading
        // then redraws the route on the fresh style.
        if context.coordinator.scheme != colorScheme {
            context.coordinator.scheme = colorScheme
            mapView.styleURL = TelemetryMap.styleURL(for: colorScheme)
        } else if let style = mapView.style {
            context.coordinator.draw(on: style, mapView: mapView)
        }
    }

    // MARK: Coordinator
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var coords: [CLLocationCoordinate2D]
        var scheme: ColorScheme

        init(coords: [CLLocationCoordinate2D], scheme: ColorScheme) {
            self.coords = coords
            self.scheme = scheme
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            draw(on: style, mapView: mapView)
        }

        func draw(on style: MLNStyle, mapView: MLNMapView) {
            guard coords.count >= 2 else { return }

            let accent = UIColor(DS.Colors.accent)

            // Route polyline ----------------------------------------------------
            var line = coords
            let polyline = MLNPolylineFeature(coordinates: &line, count: UInt(line.count))
            // lineDistanceMetrics lets the core line use a progress-based gradient
            // (start → end), so direction of travel reads through the shading.
            upsertSource(style, id: "route-src", shape: polyline,
                         options: [.lineDistanceMetrics: true])

            if let src = style.source(withIdentifier: "route-src") {
                // Soft glow underneath gives the electric line depth, and its
                // partial opacity makes self-overlapping segments stack visibly.
                if style.layer(withIdentifier: "route-glow") == nil {
                    let glow = MLNLineStyleLayer(identifier: "route-glow", source: src)
                    glow.lineColor = NSExpression(forConstantValue: accent.withAlphaComponent(0.28))
                    glow.lineWidth = NSExpression(forConstantValue: 12)
                    glow.lineBlur = NSExpression(forConstantValue: 6)
                    glow.lineCap = NSExpression(forConstantValue: "round")
                    glow.lineJoin = NSExpression(forConstantValue: "round")
                    style.addLayer(glow)
                }
                // Core line on top — gradient from a dim start to a bright finish
                // so you can read which way the drive went and where it overlaps.
                if style.layer(withIdentifier: "route-line") == nil {
                    let layer = MLNLineStyleLayer(identifier: "route-line", source: src)
                    let startColor = Self.blend(accent, toward: scheme == .dark ? .black : .white, 0.45)
                    let midColor   = accent
                    let endColor   = Self.blend(accent, toward: .white, 0.55)
                    let stops: [NSNumber: UIColor] = [0.0: startColor, 0.5: midColor, 1.0: endColor]
                    layer.lineGradient = NSExpression(
                        format: "mgl_interpolate:withCurveType:parameters:stops:($lineProgress, 'linear', nil, %@)",
                        stops)
                    layer.lineWidth = NSExpression(forConstantValue: 5)
                    layer.lineCap = NSExpression(forConstantValue: "round")
                    layer.lineJoin = NSExpression(forConstantValue: "round")
                    style.addLayer(layer)
                }
            }

            // Start and end markers — start contrasts with the basemap per scheme.
            let startFill: UIColor = scheme == .dark ? .white : UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)
            if let start = coords.first {
                upsertSource(style, id: "start-src", shape: MLNPointFeature(at: start))
                upsertCircle(style, id: "start-dot", source: "start-src",
                             fill: startFill, stroke: accent)
            }
            if let end = coords.last {
                upsertSource(style, id: "end-src", shape: MLNPointFeature(at: end))
                upsertCircle(style, id: "end-dot", source: "end-src",
                             fill: accent, stroke: accent)
            }

            // Fit the drive within the frame ------------------------------------
            let lats = coords.map(\.latitude), lngs = coords.map(\.longitude)
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: lats.min()!, longitude: lngs.min()!),
                ne: CLLocationCoordinate2D(latitude: lats.max()!, longitude: lngs.max()!)
            )
            mapView.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
                animated: false
            )
        }

        private func upsertSource(_ style: MLNStyle, id: String, shape: MLNShape,
                                  options: [MLNShapeSourceOption: Any]? = nil) {
            if let existing = style.source(withIdentifier: id) as? MLNShapeSource {
                existing.shape = shape
            } else {
                style.addSource(MLNShapeSource(identifier: id, shape: shape, options: options))
            }
        }

        /// Linearly blend `color` toward `target` by `amount` (0…1).
        static func blend(_ color: UIColor, toward target: UIColor, _ amount: CGFloat) -> UIColor {
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            target.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            let t = max(0, min(1, amount))
            return UIColor(red: r1 + (r2 - r1) * t,
                           green: g1 + (g2 - g1) * t,
                           blue: b1 + (b2 - b1) * t,
                           alpha: a1 + (a2 - a1) * t)
        }

        private func upsertCircle(_ style: MLNStyle, id: String, source: String,
                                  fill: UIColor, stroke: UIColor) {
            guard style.layer(withIdentifier: id) == nil,
                  let src = style.source(withIdentifier: source) else { return }
            let dot = MLNCircleStyleLayer(identifier: id, source: src)
            dot.circleRadius = NSExpression(forConstantValue: 5)
            dot.circleColor = NSExpression(forConstantValue: fill)
            dot.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
            dot.circleStrokeColor = NSExpression(forConstantValue: stroke)
            style.addLayer(dot)
        }
    }
}

private extension MLNPointFeature {
    convenience init(at coordinate: CLLocationCoordinate2D) {
        self.init()
        self.coordinate = coordinate
    }
}

// MARK: – MapLibre Multi-Route Representable
/// Overview map that draws several drives at once on the same keyless basemap as
/// the single-route view — each route tinted by its score, glow underneath so
/// overlapping segments stack visibly. Used by the "Routes this week" card.
struct MapLibreMultiRouteRepresentable: UIViewRepresentable {
    struct Item { let coords: [CLLocationCoordinate2D]; let color: UIColor }

    let items: [Item]
    let colorScheme: ColorScheme
    /// The blurred underlay. v2 (flat, no glow) passes false; v1 keeps the default.
    var glow: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(items: items, scheme: colorScheme, glow: glow) }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: TelemetryMap.styleURL(for: colorScheme))
        mapView.delegate = context.coordinator
        mapView.backgroundColor = UIColor(DS.Colors.bgCard)
        mapView.allowsScrolling = false
        mapView.allowsZooming = false
        mapView.allowsRotating = false
        mapView.allowsTilting = false
        mapView.compassView.isHidden = true
        mapView.showsUserLocation = false
        mapView.attributionButtonPosition = .bottomRight
        mapView.logoView.isHidden = true
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.items = items
        context.coordinator.glow = glow
        if context.coordinator.scheme != colorScheme {
            context.coordinator.scheme = colorScheme
            mapView.styleURL = TelemetryMap.styleURL(for: colorScheme)
        } else if let style = mapView.style {
            context.coordinator.draw(on: style, mapView: mapView)
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var items: [Item]
        var scheme: ColorScheme
        var glow: Bool

        init(items: [Item], scheme: ColorScheme, glow: Bool = true) {
            self.items = items
            self.scheme = scheme
            self.glow = glow
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            draw(on: style, mapView: mapView)
        }

        func draw(on style: MLNStyle, mapView: MLNMapView) {
            // The set of routes can change (e.g. switching weeks), so clear ours
            // and redraw rather than leave stale layers behind.
            for layer in style.layers where layer.identifier.hasPrefix("wr-") {
                style.removeLayer(layer)
            }
            for source in style.sources where source.identifier.hasPrefix("wr-") {
                style.removeSource(source)
            }

            let drawable = items.filter { $0.coords.count >= 2 }
            guard !drawable.isEmpty else { return }

            for (i, item) in drawable.enumerated() {
                var line = item.coords
                let polyline = MLNPolylineFeature(coordinates: &line, count: UInt(line.count))
                let src = MLNShapeSource(identifier: "wr-src-\(i)", shape: polyline, options: nil)
                style.addSource(src)

                if glow {
                    let underlay = MLNLineStyleLayer(identifier: "wr-glow-\(i)", source: src)
                    underlay.lineColor = NSExpression(forConstantValue: item.color.withAlphaComponent(0.22))
                    underlay.lineWidth = NSExpression(forConstantValue: 7)
                    underlay.lineBlur = NSExpression(forConstantValue: 4)
                    underlay.lineCap = NSExpression(forConstantValue: "round")
                    underlay.lineJoin = NSExpression(forConstantValue: "round")
                    style.addLayer(underlay)
                }

                let core = MLNLineStyleLayer(identifier: "wr-line-\(i)", source: src)
                core.lineColor = NSExpression(forConstantValue: item.color)
                core.lineWidth = NSExpression(forConstantValue: 3)
                core.lineCap = NSExpression(forConstantValue: "round")
                core.lineJoin = NSExpression(forConstantValue: "round")
                style.addLayer(core)
            }

            // Fit all routes within the frame.
            let all = drawable.flatMap(\.coords)
            let lats = all.map(\.latitude), lngs = all.map(\.longitude)
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: lats.min()!, longitude: lngs.min()!),
                ne: CLLocationCoordinate2D(latitude: lats.max()!, longitude: lngs.max()!)
            )
            mapView.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(top: 22, left: 22, bottom: 22, right: 22),
                animated: false
            )
        }
    }
}

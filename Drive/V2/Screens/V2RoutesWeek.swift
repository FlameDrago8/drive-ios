//
//  V2RoutesWeek.swift
//  Drive — v2 "Road Furniture"
//
//  "This week's routes" on Progress (Week): every drive of the calendar week
//  with GPS on one map, each line in its score band (`paint` / `okay` /
//  `poor`, the trend chart's bar colours). The card reuses the beta's
//  MapLibreMultiRouteRepresentable (same keyless basemap, attribution kept);
//  a tap opens a full, pannable map in the style of V2RouteMapSheet.
//

import SwiftUI
import CoreLocation
import MapLibre

// MARK: - Model

/// One drive's line on the week map.
struct V2WeekRoute: Identifiable, Equatable {
    let id: UUID
    let coords: [CLLocationCoordinate2D]
    /// nil for an unscored drive (drawn in `paint`, like a calm one).
    let band: V2Band?

    static func == (a: V2WeekRoute, b: V2WeekRoute) -> Bool {
        a.id == b.id && a.band == b.band && a.coords.count == b.coords.count
    }

    var color: Color {
        switch band {
        case .poor?: return V2.poor
        case .okay?: return V2.okay
        default:     return V2.paint
        }
    }

    /// The band colour resolved for the map's appearance (MapLibre takes a
    /// fixed UIColor, not a dynamic one).
    func uiColor(_ scheme: ColorScheme) -> UIColor {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        return UIColor(color).resolvedColor(with: traits)
    }

    /// Drives that ended this calendar week (the trend chart's week) with at
    /// least two usable GPS points, oldest first so the newest draws on top.
    static func thisWeek(_ facts: [V2DriveFacts], now: Date) -> [V2WeekRoute] {
        let cal = Calendar.current
        let week = cal.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: cal.startOfDay(for: now), duration: 7 * 86_400)
        let routes: [V2WeekRoute] = facts.compactMap { f in
            guard f.end >= week.start && f.end < week.end else { return nil }
            let coords = coordinates(f.session.route)
            guard coords.count >= 2 else { return nil }
            return V2WeekRoute(id: f.id, coords: coords, band: f.isScored ? f.band : nil)
        }
        return routes.reversed()
    }

    private static func coordinates(_ route: [RoutePoint]) -> [CLLocationCoordinate2D] {
        route
            .filter { $0.lat.isFinite && $0.lng.isFinite && abs($0.lat) <= 90 && abs($0.lng) <= 180
                && !($0.lat == 0 && $0.lng == 0) }
            .map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }
}

// MARK: - Card

/// "This week's routes" + "N routes", the 180 pt map, tap → full map sheet.
/// The caller hides the card when `routes` is empty.
struct V2WeekRoutesCard: View {
    let routes: [V2WeekRoute]

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingMap = false

    init(routes: [V2WeekRoute]) {
        self.routes = routes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("This week's routes")
                    .font(V2Type.subheadSemibold)
                    .foregroundStyle(V2.label)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(verbatim: countText)
                    .font(V2Type.footnoteNumbers)
                    .foregroundStyle(V2.label2)
                    .lineLimit(1)
            }
            V2WeekRoutesMap(routes: routes, colorScheme: colorScheme)
                .equatable()
                .frame(height: 180)
                .background(V2.card2)
                .overlay {
                    // Everything but MapLibre's attribution corner opens the map.
                    Button {
                        showingMap = true
                    } label: {
                        Color.clear
                            .contentShape(V2MapTapArea())
                    }
                    .buttonStyle(V2MapPressStyle())
                    .accessibilityLabel("Map of this week's routes, \(countText)")
                    .accessibilityHint("Opens a larger map")
                }
                // Clip after the overlay so the press wash keeps the map's corners.
                .clipShape(RoundedRectangle(cornerRadius: V2.radiusPhoto, style: .continuous))
        }
        .v2Card()
        .padding(.top, V2.moduleGap)
        .sheet(isPresented: $showingMap) {
            V2WeekRoutesSheet(routes: routes)
                .v2AppScheme()
        }
    }

    private var countText: String {
        routes.count == 1 ? "1 route" : "\(routes.count) routes"
    }
}

/// The card's map: an Equatable wrapper so Progress re-rendering (Game
/// Center, library updates) doesn't make the representable redraw its layers.
fileprivate struct V2WeekRoutesMap: View, Equatable {
    let routes: [V2WeekRoute]
    let colorScheme: ColorScheme

    var body: some View {
        MapLibreMultiRouteRepresentable(
            items: routes.map { r in
                MapLibreMultiRouteRepresentable.Item(coords: r.coords, color: r.uiColor(colorScheme))
            },
            colorScheme: colorScheme
        )
        .accessibilityHidden(true)
    }
}

/// The map's tap area: the whole rect minus the bottom-trailing corner that
/// holds MapLibre's attribution button, so the credit stays tappable.
fileprivate struct V2MapTapArea: Shape {
    func path(in rect: CGRect) -> Path {
        let cw = min(48, rect.width)
        let ch = min(40, rect.height)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - ch))
        p.addLine(to: CGPoint(x: rect.maxX - cw, y: rect.maxY - ch))
        p.addLine(to: CGPoint(x: rect.maxX - cw, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Touch feedback on the map: a `fill` wash, never a scale.
fileprivate struct V2MapPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(V2.fill.opacity(configuration.isPressed ? 1 : 0))
            // The whole button hit-tests as the tap area, so the attribution corner stays the map's.
            .contentShape(V2MapTapArea())
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Full map sheet

/// Pan and pinch over the week's routes; Done closes.
struct V2WeekRoutesSheet: View {
    let routes: [V2WeekRoute]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(routes: [V2WeekRoute]) {
        self.routes = routes
    }

    var body: some View {
        NavigationStack {
            V2InteractiveWeekMap(routes: routes, colorScheme: colorScheme)
                .background(V2.card)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityLabel("Map of this week's routes")
                .navigationTitle("This week's routes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// Same basemap (`TelemetryMap`), flat 4 pt lines in band colours (no glow),
/// newest on top. Fitted once; after that the camera is the user's.
fileprivate struct V2InteractiveWeekMap: UIViewRepresentable {
    let routes: [V2WeekRoute]
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(routes: routes, scheme: colorScheme)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: TelemetryMap.styleURL(for: colorScheme))
        mapView.delegate = context.coordinator
        mapView.backgroundColor = UIColor(V2.card)

        // Pan and pinch; no rotation or tilt (flat, north up), no user dot.
        mapView.allowsScrolling = true
        mapView.allowsZooming = true
        mapView.allowsRotating = false
        mapView.allowsTilting = false
        mapView.compassView.isHidden = true
        mapView.showsUserLocation = false

        // OSM/provider attribution stays visible for license compliance.
        mapView.attributionButtonPosition = .bottomRight
        mapView.logoView.isHidden = true
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        // Only an appearance flip changes anything: reload the basemap, and
        // didFinishLoading redraws the routes on the fresh style.
        guard context.coordinator.scheme != colorScheme else { return }
        context.coordinator.scheme = colorScheme
        mapView.styleURL = TelemetryMap.styleURL(for: colorScheme)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        let routes: [V2WeekRoute]
        var scheme: ColorScheme
        private var fitted = false

        init(routes: [V2WeekRoute], scheme: ColorScheme) {
            self.routes = routes
            self.scheme = scheme
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            draw(on: style)
            fitOnce(mapView)
        }

        private func draw(on style: MLNStyle) {
            for (i, route) in routes.enumerated() where route.coords.count >= 2 {
                let sourceID = "v2-week-src-\(i)"
                guard style.source(withIdentifier: sourceID) == nil else { continue }
                var line = route.coords
                let polyline = MLNPolylineFeature(coordinates: &line, count: UInt(line.count))
                let source = MLNShapeSource(identifier: sourceID, shape: polyline, options: nil)
                style.addSource(source)

                let layer = MLNLineStyleLayer(identifier: "v2-week-line-\(i)", source: source)
                layer.lineColor = NSExpression(forConstantValue: route.uiColor(scheme))
                layer.lineWidth = NSExpression(forConstantValue: 4)
                layer.lineCap = NSExpression(forConstantValue: "round")
                layer.lineJoin = NSExpression(forConstantValue: "round")
                style.addLayer(layer)
            }
        }

        /// Frame every route once the view has a size; never again, so a pan
        /// or zoom (or an appearance flip) keeps the user's camera.
        private func fitOnce(_ mapView: MLNMapView) {
            guard !fitted else { return }
            let all = routes.flatMap { $0.coords }
            guard all.count >= 2 else { return }
            guard mapView.bounds.width > 0, mapView.bounds.height > 0 else {
                DispatchQueue.main.async { [weak self, weak mapView] in
                    guard let self, let mapView, mapView.bounds.width > 0, mapView.bounds.height > 0 else { return }
                    self.fitOnce(mapView)
                }
                return
            }
            fitted = true
            let lats = all.map { $0.latitude }
            let lngs = all.map { $0.longitude }
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLng = lngs.min(), let maxLng = lngs.max() else { return }
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLng),
                ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLng)
            )
            mapView.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(top: 48, left: 32, bottom: 48, right: 32),
                animated: false
            )
        }
    }
}

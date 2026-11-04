import Foundation

@main
struct RegressionTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); checks += 1
    }
    static func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
    static func main() throws {
        // Viewport and hinge examples are synthetic; no physical device dimensions assumed.
        let phoneLayout = DashboardLayout(width: 390)
        check(phoneLayout.capacity(compact: true, gauge: false, wide: false, accessible: false) == 2, "Compact phone metrics should fit two columns")
        check(phoneLayout.capacity(compact: false, gauge: false, wide: false, accessible: false) == 1, "Phone charts must remain readable")
        check(phoneLayout.capacity(compact: true, gauge: false, wide: true, accessible: false) == 2, "Number panels should retain compact tiles regardless of Grafana grid span")
        let narrowLayout = DashboardLayout(width: 280)
        check(narrowLayout.capacity(compact: true, gauge: false, wide: false, accessible: false) == 1, "Narrow windows should use one metric column")
        let openLayout = DashboardLayout(width: 744)
        check(openLayout.capacity(compact: false, gauge: false, wide: false, accessible: false) == 2, "Open viewports should fit two charts")
        let bookLayout = DashboardLayout(width: 940, division: CGRect(x: 440, y: 0, width: 60, height: 700))
        let bookCapacity = bookLayout.capacity(compact: true, gauge: false, wide: false, accessible: false)
        check(bookCapacity == 4, "Book metrics should use an even number of columns")
        let tile = bookLayout.panelWidth(at: 0, capacity: bookCapacity, spacing: 12)
        check(tile * 2 + 12 == bookLayout.leadingWidth, "Leading tiles must end before the hinge")
        check(bookLayout.gap(after: 1, capacity: 4, spacing: 12) == 60, "Center spacing must clear the hinge")
        check(bookLayout.panelWidth(at: 0, capacity: 1, spacing: 16) == bookLayout.trailingWidth, "Wide panels must stay within a usable region")
        check(bookLayout.capacity(compact: true, gauge: false, wide: false, accessible: true) == 1, "Accessibility sizes must use one card per row")
        check(openLayout.capacity(compact: true, gauge: false, wide: false, accessible: false) == 4, "Unfolding should restore normal metric capacity")
        check(DashboardLayout(width: 0).panelWidth(at: 0, capacity: 1, spacing: 16) == 0, "Transient zero-width viewports must remain valid")

        let original = try json(#"{"id":1,"uid":"test","title":"Before","version":7,"schemaVersion":39,"templating":{"list":[{"name":"host"}]},"annotations":{"list":[]},"pluginSetting":{"keep":true},"panels":[{"id":1,"type":"timeseries","title":"Temperature","fieldConfig":{"defaults":{"unit":"fahrenheit"}},"options":{"legend":{"showLegend":true}},"transformations":[{"id":"organize"}],"targets":[{"refId":"A","expr":"temperature","legendFormat":"Room"}]}]}"#)
        let dashboard = DashboardDetail(document: original.object!)
        let edited = dashboard.updatingMetadata(title: "After", description: "New description", tags: ["important"])
        for key in ["panels", "templating", "annotations", "pluginSetting", "schemaVersion", "version"] {
            check(edited[key] == original[key], "Metadata edit dropped \(key)")
        }
        let encoded = try JSONEncoder().encode(DashboardSaveRequest(dashboard: edited, folderUid: "folder", message: "test", overwrite: false))
        let request = try JSONDecoder().decode(JSONValue.self, from: encoded)
        check(request["overwrite"] == .bool(false), "Version protection must remain enabled")
        check(request["dashboard"]?["panels"] == original["panels"], "Encoding lost graph configuration")
        check(request["dashboard"]?["title"] == .string("After"), "Title not changed")
        check(dashboard.allowsNativeRendering, "Unused variables should not disable unrelated panels")
        let annotated = DashboardDetail(document: try json(#"{"annotations":{"list":[{"builtIn":1,"enable":true,"target":{"type":"dashboard"}}]}}"#).object!)
        check(annotated.allowsNativeRendering && annotated.hasNativeAnnotations, "Built-in annotations should be supported")
        let customAnnotated = DashboardDetail(document: try json(#"{"annotations":{"list":[{"enable":true,"expr":"custom"}]}}"#).object!)
        check(!customAnnotated.allowsNativeRendering, "Custom annotation queries need Grafana")
        let malformedVariables = try JSONDecoder().decode(DashboardDetail.self, from: Data(#"{"title":"Vars","templating":{"list":[{"label":"no name"}]},"panels":[{"id":1,"type":"stat"}]}"#.utf8))
        check(malformedVariables.templating == nil && malformedVariables.allPanels.count == 1, "Malformed template variables must not fail dashboard loading")

        let nested = DashboardDetail(document: try json(#"{"panels":[{"id":1,"type":"stat"},{"id":2,"type":"row","title":"Room","panels":[{"id":3,"type":"text"}]},{"id":4,"type":"timeseries"}]}"#).object!)
        check(nested.sections.count == 2, "Row grouping lost")
        check(nested.allPanels.map(\.id) == [1,3,4], "Text or nested panels lost")
        check(nested.sections[1].title == "Room", "Row heading lost")

        var panel = try json(#"{"id":1,"type":"timeseries","fieldConfig":{"defaults":{"unit":"fahrenheit","custom":{"stacking":{"mode":"none"},"scaleDistribution":{"type":"linear"}}}},"targets":[{"refId":"A","expr":"temperature","datasource":{"uid":"prom","type":"prometheus"}}]}"#).object!
        check(NativePanelConfiguration.supported(Panel(document: panel)) != nil, "Basic panel should be supported")
        panel["transformations"] = .array([.object(["id": .string("organize")])])
        check(NativePanelConfiguration.supported(Panel(document: panel)) == nil, "Transforms must fall back")
        panel["transformations"] = .array([])
        panel["fieldConfig"] = try json(#"{"defaults":{"custom":{"stacking":{"mode":"normal"}}}}"#)
        check(NativePanelConfiguration.supported(Panel(document: panel)) == nil, "Stacked panels must fall back")
        panel["fieldConfig"] = try json(#"{"defaults":{"custom":{"scaleDistribution":{"type":"log"}}}}"#)
        check(NativePanelConfiguration.supported(Panel(document: panel)) == nil, "Log panels must fall back")
        panel["fieldConfig"] = try json(#"{"defaults":{"custom":{"transform":"negative-Y"}}}"#)
        check(NativePanelConfiguration.supported(Panel(document: panel)) == nil, "Value transforms must fall back")
        panel["type"] = .string("gauge"); panel["fieldConfig"] = .object([:])
        check(NativePanelConfiguration.supported(Panel(document: panel)) == nil, "Auto-range gauge needs Grafana")
        panel["fieldConfig"] = try json(#"{"defaults":{"min":0,"max":100,"unit":"percent","thresholds":{"mode":"absolute","steps":[{"value":null,"color":"blue"},{"value":80,"color":"red"}]}}}"#)
        let gauge = NativePanelConfiguration.supported(Panel(document: panel))
        check(gauge?.thresholds.first?.color == "blue" && gauge?.thresholds.first?.value == nil, "Base threshold lost")

        let frames = try json(#"{"results":{"A":{"frames":[{"schema":{"fields":[{"name":"temperature","type":"number","labels":{"room":"Office"}},{"name":"time","type":"time"},{"name":"humidity","type":"number","labels":{"room":"Office"}}]},"data":{"values":[[20,null,22,23],[1000,2000,3000,4000],[40,41,42,43]]}}]}}}"#)
        let targets: [[String: JSONValue]] = [["refId": .string("A"), "legendFormat": .string("{{room}}")]]
        let decoded = try NativeFrameDecoder.decode(frames, targets: targets)
        check(decoded.count == 2, "Must decode every numeric field, regardless of column order")
        check(decoded[0].name == "Office", "Legend template not evaluated")
        check(decoded[0].segments.count == 2, "Must break lines at null values")
        check(decoded[0].samples[1].value == nil, "Null must not become zero")
        check(decoded[0].latest == 23, "Incorrect latest value")
        check(decoded[0].samples[0].timestamp.timeIntervalSince1970 == 1, "Timestamp milliseconds not converted")
        let bad = try json(#"{"results":{"A":{"error":"Permission denied","status":403}}}"#)
        do { _ = try NativeFrameDecoder.decode(bad, targets: targets); fatalError("Query errors must not look like no data") }
        catch NativePanelError.queryFailed { checks += 1 }
        let misaligned = try json(#"{"results":{"A":{"frames":[{"schema":{"fields":[{"name":"time","type":"time"},{"name":"Value","type":"number"}]},"data":{"values":[[1000,2000],[2]]}}]}}}"#)
        do { _ = try NativeFrameDecoder.decode(misaligned, targets: targets); fatalError("Malformed columns must be rejected") }
        catch NativePanelError.invalidFrames { checks += 1 }
        check(MetricFormat.string(.infinity) == "—", "Non-finite values must not crash")
        check(MetricFormat.string(.nan) == "—", "NaN must not crash")
        check(MetricFormat.string(nil) == "—", "Missing values must not become zero")
        check(MetricFormat.string(-2048, unit: "bytes").contains("-2 KiB"), "Signed binary units are wrong")
        check(MetricFormat.string(0.45, unit: "percentunit").contains("45%"), "Fractional percent is wrong")
        check(!MetricFormat.string(1e30).isEmpty, "Large values must not overflow an Int")
        check(GrafanaAPIClient.relativeSeconds("now-5m") == 300, "Wrong 5m range")
        check(GrafanaAPIClient.relativeSeconds("now-30d") == 2592000, "Wrong 30d range")
        check(GrafanaAPIClient.relativeSeconds("now-inf") == nil, "Invalid range must be rejected")
        check(GrafanaAPIClient.relativeSeconds("now-1e308d") == nil, "Overflowing time ranges must be rejected")
        check(MetricFormat.string(1, decimals: 2) == "1.00", "Explicit decimal precision must be preserved")
        try authenticationResponses()
        print("Passed \(checks) GrafLens regression checks.")
    }
    static func authenticationResponses() throws {
        func result(_ status: Int, _ body: String, mime: String? = "application/json",
                    path: String = "/api/health") -> String {
            let response = HTTPURLResponse(url: URL(string: "https://grafana.example" + path)!,
                statusCode: status, httpVersion: nil, headerFields: mime.map { ["Content-Type": $0] })!
            do {
                try GrafanaAPIClient.validateAPIResponse(data: Data(body.utf8), response: response)
                return "ok"
            } catch let error as GrafanaAPIError {
                switch error {
                case .unauthorized: return "unauthorized"
                case .forbidden: return "forbidden"
                case .webSignInRequired: return "login"
                case .webPageReturned: return "html"
                case .notFound: return "notFound"
                case .serverError(let status): return "server:\(status)"
                default: return "unexpected"
                }
            } catch { return "unexpected" }
        }
        check(result(401, #"{"message":"Invalid API key"}"#) == "unauthorized", "A Grafana-shaped 401 must not assert a particular rejection source")
        check(result(401, "<html>Unauthorized proxy</html>", mime: "text/html") == "unauthorized", "An HTML proxy 401 needs authentication guidance")
        check(result(403, "<html>Access denied</html>", mime: "text/html") == "forbidden", "A proxy 403 must not be blamed solely on Grafana permissions")
        check(result(200, "<html>Sign in</html>", mime: "text/html", path: "/if/flow/login/?token=secret") == "login", "An Authentik flow redirect should explain browser authentication")
        check(result(200, "<html>Sign in</html>", mime: "text/html", path: "/grafana/login") == "login", "Grafana subpath login redirects should be recognized")
        check(result(200, "<html><input type='password'></html>", mime: "text/html") == "login", "A login form returned at the API URL should be recognized")
        check(result(200, "<html>Welcome</html>", mime: "text/html") == "html", "An arbitrary HTML page must not be called a proven login failure")
        check(result(200, " \u{FEFF}<!DOCTYPE html><html>Welcome</html>", mime: nil) == "html", "Detect HTML without a Content-Type header")
        check(result(200, "<html>Welcome</html>", mime: "application/json") == "html", "Detect mislabeled HTML")
        check(result(200, "<?xml version='1.0'?><html/>", mime: "application/xhtml+xml") == "html", "Detect XHTML responses")
        check(result(502, "<html>Bad Gateway</html>", mime: "text/html") == "server:502", "Keep gateway failures distinct from login problems")
        check(result(404, "<html>Not found</html>", mime: "text/html") == "notFound", "Keep a wrong API path distinct from login problems")
        check(result(200, #"{"version":"13","message":"<html>login</html>"}"#) == "ok", "HTML strings inside valid JSON must not trigger a login error")
        check(result(200, #"{"ok":true}"#, path: "/login/api/health") == "ok", "URL names alone must not reject JSON")
        check(result(204, "") == "ok", "Empty successful responses retain their existing decoding behavior")
        check(result(200, "malformed JSON") == "ok", "Non-HTML parsing failures retain their existing decoding behavior")
        check(GrafanaAPIError.unauthorized.localizedDescription.contains("proxy")
              && !GrafanaAPIError.unauthorized.localizedDescription.contains("v13"), "401 guidance must not infer the server version")
        let privateResponse = HTTPURLResponse(url: URL(string: "https://idp.example/if/flow/login/?code=private-code")!,
            statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
        do {
            try GrafanaAPIClient.validateAPIResponse(data: Data("<html>private-body</html>".utf8), response: privateResponse)
            preconditionFailure("Expected login diagnostic")
        } catch {
            check(!error.localizedDescription.contains("private-code") && !error.localizedDescription.contains("private-body"),
                  "Login diagnostics must not expose response bodies or redirect query values")
        }
    }

}

// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@main struct SelectionTests {
    static func main() {
        let processes = [
            AudioProcess(object: 100, pid: 100, rawBundle: "com.apple.WebKit.GPU", key: "bundle:com.apple.Safari", name: "Safari", output: true),
            AudioProcess(object: 101, pid: 101, rawBundle: "com.apple.WebKit.GPU", key: "bundle:com.apple.mail", name: "Mail", output: true),
            AudioProcess(object: 102, pid: 102, rawBundle: "com.google.Chrome.helper", key: "bundle:com.google.Chrome", name: "Chrome", output: true),
            AudioProcess(object: 103, pid: 103, rawBundle: "org.macam.Macam", key: CaptureSelection.ownKey, name: "Macam", output: false),
        ]
        let catalog = ProcessCatalog(processes: processes, applications: [])
        var selected = CaptureSelection()
        selected.wholeSystem = false; selected.applications = ["bundle:com.apple.Safari"]
        let safari = catalog.configuration(selected)
        precondition(safari.objects == [100], "Safari selection must not include Mail's WebKit helper")
        precondition(!safari.bundles.contains("com.apple.WebKit.GPU"), "A shared helper bundle ID would broaden the selection")
        precondition(safari.bundles.contains("com.apple.Safari"))
        selected.applications.insert("bundle:com.apple.mail")
        precondition(catalog.configuration(selected).objects == [100, 101])
        selected.applications = ["bundle:com.google.Chrome", CaptureSelection.ownKey]
        precondition(catalog.configuration(selected).objects == [102], "Chrome is captured by default; Macam itself is always excluded")
        let whole = catalog.configuration(CaptureSelection())
        precondition(whole.objects == [103], "Default whole-system tap must exclude only Macam")
        precondition(!whole.bundles.contains("com.google.Chrome.helper"))
        precondition(CaptureSelection().excludedApplications.isEmpty)

        // Receiving a stream does not identify an application's output as unwanted.
        // All four browser routes must keep the source, including same-browser use.
        for source in ["com.google.Chrome", "com.apple.Safari"] {
            for receiver in ["com.google.Chrome", "com.apple.Safari"] {
                var route = CaptureSelection(); route.wholeSystem = false
                route.applications = ["bundle:" + source]
                precondition(!route.isExcluded("bundle:" + receiver))
                precondition(catalog.configuration(route).objects == (source == "com.google.Chrome" ? [102] : [100]))
            }
        }
        var explicit = CaptureSelection(); explicit.excludedApplications = ["bundle:com.google.Chrome"]
        precondition(catalog.configuration(explicit).objects == [102, 103])
        precondition(catalog.configuration(explicit).bundles.contains("com.google.Chrome.helper"))
        explicit.wholeSystem = false; explicit.applications = ["bundle:com.google.Chrome"]
        precondition(catalog.configuration(explicit).objects.isEmpty)
        explicit.excludedApplications = []
        precondition(catalog.configuration(explicit).objects == [102], "Turning exclusion off restores Chrome capture")
        var allBrowsers = CaptureSelection(); allBrowsers.excludedApplications = [CaptureSelection.allBrowsers]
        precondition(catalog.configuration(allBrowsers).objects == [100, 101, 102, 103], "Conservative browser exclusion includes shared WebKit hosts")
        selected.applications = ["bundle:org.macam.nonexistent"]
        precondition(catalog.configuration(selected).objects.isEmpty)

        // Old personal defaults must not silently re-enable exclusion on upgrade.
        let legacy = Data(#"{"wholeSystem":false,"applications":["bundle:com.apple.Safari"],"receiver":"bundle:com.google.Chrome"}"#.utf8)
        let migrated = try! JSONDecoder().decode(CaptureSelection.self, from: legacy)
        precondition(migrated.excludedApplications.isEmpty && migrated.applications == ["bundle:com.apple.Safari"])
        let saved = try! JSONEncoder().encode(explicit)
        precondition(try! JSONDecoder().decode(CaptureSelection.self, from: saved) == explicit)
        explicit.excludedApplications = ["bundle:com.apple.Safari"]
        precondition(try! JSONDecoder().decode(CaptureSelection.self, from: JSONEncoder().encode(explicit)) == explicit)

        var multiple = CaptureSelection()
        multiple.excludedApplications = ["bundle:com.google.Chrome", "bundle:com.apple.Safari"]
        precondition(catalog.configuration(multiple).objects == [100, 102, 103], "Union must exclude both browsers while retaining Mail's shared helper")
        precondition(!catalog.configuration(multiple).bundles.contains("com.apple.WebKit.GPU"))
        multiple.excludedApplications.remove("bundle:com.google.Chrome")
        precondition(catalog.configuration(multiple).objects == [100, 103], "Unchecking one app must retain the other exclusion")
        multiple.excludedApplications.removeAll()
        precondition(catalog.configuration(multiple).objects == [103])
        multiple.wholeSystem = false
        multiple.applications = ["bundle:com.apple.Safari", "bundle:com.google.Chrome", "bundle:com.apple.mail"]
        multiple.excludedApplications = ["bundle:com.google.Chrome", "bundle:com.apple.mail"]
        precondition(catalog.configuration(multiple).objects == [100], "Multiple exclusions must also filter selected-source mode")
        let previous = Data(#"{"wholeSystem":true,"applications":[],"excludedApplication":"bundle:com.google.Chrome"}"#.utf8)
        precondition(try! JSONDecoder().decode(CaptureSelection.self, from: previous).excludedApplications == ["bundle:com.google.Chrome"])
        let cleared = Data(#"{"excludedApplications":[],"excludedApplication":"bundle:com.google.Chrome"}"#.utf8)
        precondition(try! JSONDecoder().decode(CaptureSelection.self, from: cleared).excludedApplications.isEmpty)
        precondition(try! JSONDecoder().decode(CaptureSelection.self, from: JSONEncoder().encode(multiple)) == multiple)
        let cli = try! selectionFromArguments(["Macam", "--exclude", "com.google.Chrome", "--exclude", "com.apple.Safari", "--exclude", "com.google.Chrome"])
        precondition(cli.excludedApplications == ["bundle:com.google.Chrome", "bundle:com.apple.Safari"])
        precondition(try! selectionFromArguments(["Macam", "--exclude", "com.google.Chrome", "--exclude", "none"]).excludedApplications.isEmpty)
        let clearedThenAdded = try! selectionFromArguments(["Macam", "--exclude", "none", "--receiver", "com.apple.Safari"])
        precondition(clearedThenAdded.excludedApplications == ["bundle:com.apple.Safari"])
        print("Source-selection tests passed (all four browser routes, multiple exclusions, preference migration, shared helpers).")
    }
}

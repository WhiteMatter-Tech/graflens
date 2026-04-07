import CoreSpotlight
import MobileCoreServices

enum SpotlightManager {

    static let domainDashboard = "tech.whitematter.graflens.dashboard"

    static func indexDashboards(_ dashboards: [DashboardSearchResult]) {
        let items = dashboards.map { dashboard -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .item)
            attributes.title = dashboard.title
            attributes.contentDescription = "Grafana Dashboard — \(dashboard.displayFolderTitle)"
            if let tags = dashboard.tags, !tags.isEmpty {
                attributes.keywords = tags
            }

            return CSSearchableItem(
                uniqueIdentifier: dashboard.uid,
                domainIdentifier: domainDashboard,
                attributeSet: attributes
            )
        }

        CSSearchableIndex.default().indexSearchableItems(items)
    }

    static func deindexAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainDashboard])
    }

    static func deindexDashboard(uid: String) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [uid])
    }
}

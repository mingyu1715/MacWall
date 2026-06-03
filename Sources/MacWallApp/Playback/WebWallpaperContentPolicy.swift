import WebKit

@MainActor
enum WebWallpaperContentPolicy {
    static func install(
        into userContentController: WKUserContentController,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let rules = #"""
        [{"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}}]
        """#
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "io.github.mingyu1715.MacWall.BlockRemote",
            encodedContentRuleList: rules
        ) { ruleList, error in
            DispatchQueue.main.async {
                guard error == nil, let ruleList else {
                    completion(false)
                    return
                }
                userContentController.add(ruleList)
                completion(true)
            }
        }
    }
}

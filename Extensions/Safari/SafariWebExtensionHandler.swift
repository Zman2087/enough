import SafariServices

/// Native half of the Safari extension. The content script is still a stub.
/// Version 1 should answer with the on-device cap from the App Group.
/// It does not receive page contents.
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let response = NSExtensionItem()
        response.userInfo = [
            SFExtensionMessageKey: [
                "status": "stub"
            ]
        ]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}

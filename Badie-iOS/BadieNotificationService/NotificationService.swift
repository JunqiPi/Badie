import Intents
import UserNotifications

/// 聊天推送换成带头像的聊天通知（Communication Notification）：下载发消息的人的头像，
/// 告诉系统这是谁在哪个会话里发的消息。服务器在推送里放了 chat（会话、发消息的人、头像地址、群名、人数）。
/// 不是聊天推送、下载失败或者超时，都按原样显示
final class NotificationService: UNNotificationServiceExtension {
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var original: UNNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let chat = ChatPush(request.content.userInfo) else { return contentHandler(request.content) }
        self.contentHandler = contentHandler
        original = request.content
        Task {
            deliver(await chat.decorate(request.content))
        }
    }

    /// 系统给的时间快用完了（约 30 秒）：先按原样显示
    override func serviceExtensionTimeWillExpire() {
        if let original { deliver(original) }
    }

    private func deliver(_ content: UNNotificationContent) {
        lock.lock()
        defer { lock.unlock() }
        contentHandler?(content)
        contentHandler = nil
    }
}

/// 推送里的 chat
struct ChatPush {
    let thread: String
    let senderId: String
    let senderName: String?
    let avatar: URL?
    /// 群聊的名字（球群名 / 球局的球馆名）；私信为空
    let group: String?
    /// 会话里一共几个人（私信为空）
    let members: Int?

    init?(_ userInfo: [AnyHashable: Any]) {
        guard let chat = userInfo["chat"] as? [String: Any],
              let thread = chat["thread"] as? String,
              let senderId = chat["sender"] as? String else { return nil }
        self.thread = thread
        self.senderId = senderId
        senderName = chat["name"] as? String
        avatar = (chat["avatar"] as? String).flatMap(URL.init(string:))
        group = chat["group"] as? String
        members = chat["members"] as? Int
    }

    func decorate(_ content: UNNotificationContent) async -> UNNotificationContent {
        let sender = INPerson(
            personHandle: INPersonHandle(value: senderId, type: .unknown),
            nameComponents: nil,
            displayName: senderName ?? content.title,
            image: await avatarImage(),
            contactIdentifier: nil,
            customIdentifier: senderId
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: group.map { INSpeakableString(spokenPhrase: $0) },
            conversationIdentifier: thread,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )
        // 群聊：除了自己和发消息的人，还有几个人（不知道每个人是谁，只告诉系统人数）
        if group != nil, let members {
            let metadata = INSendMessageIntentDonationMetadata()
            metadata.recipientCount = max(members - 2, 1)
            intent.donationMetadata = metadata
        }
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        try? await interaction.donate()
        return (try? content.updating(from: intent)) ?? content
    }

    private func avatarImage() async -> INImage? {
        guard let avatar else { return nil }
        var request = URLRequest(url: avatar)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return INImage(imageData: data)
    }
}

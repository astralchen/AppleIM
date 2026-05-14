import Testing
import Foundation

@testable import AppleIM

extension AppleIMTests {
    @Test func serverMessageSendConfigurationRequiresExplicitBaseURL() async throws {
        let missingConfiguration = ServerMessageSendService.Configuration.fromEnvironment([:], token: "secret_token")
        let missingTokenConfiguration = ServerMessageSendService.Configuration.fromEnvironment(
            ["CHATBRIDGE_SERVER_BASE_URL": "https://api.example.com"],
            token: nil
        )
        let configuration = try #require(
            ServerMessageSendService.Configuration.fromEnvironment(
                [
                    "CHATBRIDGE_SERVER_BASE_URL": "https://api.example.com",
                    "CHATBRIDGE_SERVER_TIMEOUT_SECONDS": "7"
                ],
                token: "secret_token"
            )
        )

        #expect(missingConfiguration == nil)
        #expect(missingTokenConfiguration == nil)
        #expect(configuration.baseURL.absoluteString == "https://api.example.com")
        #expect(configuration.timeoutSeconds == 7)
        #expect(await configuration.authTokenProvider() == "secret_token")
    }

    @Test func tokenRefreshActorReturnsCachedTokenAndPersistsRefresh() async throws {
        let suiteName = "AppleIMTests.TokenRefresh.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let sessionStore = UserDefaultsAccountSessionStore(userDefaults: userDefaults)
        let session = AccountSession(
            userID: "refresh_user",
            displayName: "Refresh User",
            token: "old_token",
            loggedInAt: 1
        )
        try sessionStore.saveSession(session)
        let httpClient = RecordingHTTPClient(
            tokenRefreshResponse: ServerTokenRefreshResponse(token: "new_token")
        )
        let tokenActor = TokenRefreshActor(
            session: session,
            sessionStore: sessionStore,
            httpClient: httpClient
        )

        let cachedToken = await tokenActor.validToken()
        let refreshedToken = await tokenActor.refreshToken()
        let persistedSession = sessionStore.loadSession()
        let request = await httpClient.lastTokenRefreshRequest

        #expect(cachedToken == "old_token")
        #expect(refreshedToken == "new_token")
        #expect(await tokenActor.validToken() == "new_token")
        #expect(persistedSession?.token == "new_token")
        #expect(request?.token == "old_token")
    }

    @Test func tokenRefreshActorCoalescesConcurrentRefreshes() async throws {
        let sessionStore = InMemoryAccountSessionStore(
            session: AccountSession(
                userID: "coalesce_user",
                displayName: "Coalesce User",
                token: "coalesce_old_token",
                loggedInAt: 1
            )
        )
        let httpClient = RecordingHTTPClient(
            tokenRefreshResponse: ServerTokenRefreshResponse(token: "coalesce_new_token"),
            delayNanoseconds: 100_000_000
        )
        let tokenActor = TokenRefreshActor(
            session: try #require(sessionStore.loadSession()),
            sessionStore: sessionStore,
            httpClient: httpClient
        )

        async let first = tokenActor.refreshToken()
        async let second = tokenActor.refreshToken()
        async let third = tokenActor.refreshToken()
        let tokens = await [first, second, third]

        #expect(tokens == ["coalesce_new_token", "coalesce_new_token", "coalesce_new_token"])
        #expect(await httpClient.tokenRefreshCallCount == 1)
        #expect(sessionStore.loadSession()?.token == "coalesce_new_token")
    }

    @Test func serverMessageSendConfigurationUsesTokenProviderActor() async throws {
        let sessionStore = InMemoryAccountSessionStore(
            session: AccountSession(
                userID: "provider_user",
                displayName: "Provider User",
                token: "provider_old_token",
                loggedInAt: 1
            )
        )
        let tokenActor = TokenRefreshActor(
            session: try #require(sessionStore.loadSession()),
            sessionStore: sessionStore,
            httpClient: RecordingHTTPClient(tokenRefreshResponse: ServerTokenRefreshResponse(token: "provider_new_token"))
        )
        let authTokenProvider: @Sendable () async -> String? = {
            await tokenActor.validToken()
        }
        let optionalConfiguration = ServerMessageSendService.Configuration.fromEnvironment(
            ["CHATBRIDGE_SERVER_BASE_URL": "https://api.example.com"],
            authTokenProvider: authTokenProvider
        )
        let configuration = try #require(optionalConfiguration)

        #expect(await configuration.authTokenProvider() == "provider_old_token")
        _ = await tokenActor.refreshToken()
        #expect(await configuration.authTokenProvider() == "provider_new_token")
    }

    @Test func serverMessageSendServiceMapsTextAckToSendResult() async throws {
        let httpClient = RecordingHTTPClient(
            response: ServerTextMessageSendResponse(
                serverMessageID: "server_contract_ack",
                sequence: 42,
                serverTime: 1_777_777_777
            )
        )
        let service = ServerMessageSendService(httpClient: httpClient)
        let message = makeStoredTextMessage(
            messageID: "local_contract_message",
            conversationID: "contract_conversation",
            senderID: "contract_user",
            clientMessageID: "client_contract_message",
            text: "Hello server"
        )

        let result = await service.sendText(message: message)
        let request = await httpClient.lastTextRequest

        #expect(result == .success(MessageSendAck(serverMessageID: "server_contract_ack", sequence: 42, serverTime: 1_777_777_777)))
        #expect(request?.conversationID == "contract_conversation")
        #expect(request?.clientMessageID == "client_contract_message")
        #expect(request?.senderID == "contract_user")
        #expect(request?.text == "Hello server")
        #expect(request?.localTime == 100)
    }

    @Test func serverMessageSendServiceMapsTransportFailuresToSendFailures() async throws {
        let offlineService = ServerMessageSendService(
            httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.offline)
        )
        let timeoutService = ServerMessageSendService(
            httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.timeout)
        )
        let ackMissingService = ServerMessageSendService(
            httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.ackMissing)
        )
        let message = makeStoredTextMessage()

        let offlineResult = await offlineService.sendText(message: message)
        let timeoutResult = await timeoutService.sendText(message: message)
        let ackMissingResult = await ackMissingService.sendText(message: message)

        #expect(offlineResult == .failure(.offline))
        #expect(timeoutResult == .failure(.timeout))
        #expect(ackMissingResult == .failure(.ackMissing))
    }

    @Test func serverMessageSendServiceMapsImageAckToSendResult() async throws {
        let httpClient = RecordingHTTPClient(
            response: ServerTextMessageSendResponse(
                serverMessageID: "server_image_ack",
                sequence: 43,
                serverTime: 1_777_777_743
            )
        )
        let service = ServerMessageSendService(httpClient: httpClient)
        let message = makeStoredImageMessage(
            messageID: "local_image_message",
            conversationID: "image_conversation",
            senderID: "image_user",
            clientMessageID: "client_image_message"
        )
        let upload = MediaUploadAck(mediaID: "image_media_uploaded", cdnURL: "https://cdn.example/image.png", md5: "image-md5")

        let result = await service.sendImage(message: message, upload: upload)
        let request = await httpClient.lastImageRequest

        #expect(result == .success(MessageSendAck(serverMessageID: "server_image_ack", sequence: 43, serverTime: 1_777_777_743)))
        #expect(request?.conversationID == "image_conversation")
        #expect(request?.clientMessageID == "client_image_message")
        #expect(request?.senderID == "image_user")
        #expect(request?.mediaID == "image_media_uploaded")
        #expect(request?.cdnURL == "https://cdn.example/image.png")
        #expect(request?.md5 == "image-md5")
        #expect(request?.width == 320)
        #expect(request?.height == 240)
        #expect(request?.sizeBytes == 4_096)
        #expect(request?.format == "png")
        #expect(request?.localTime == 100)
    }

    @Test func serverMessageSendServiceMapsVoiceVideoAndFileRequests() async throws {
        let httpClient = RecordingHTTPClient(
            response: ServerTextMessageSendResponse(
                serverMessageID: "server_media_ack",
                sequence: 44,
                serverTime: 1_777_777_744
            )
        )
        let service = ServerMessageSendService(httpClient: httpClient)
        let upload = MediaUploadAck(mediaID: "uploaded_media", cdnURL: "https://cdn.example/media", md5: "media-md5")

        let voiceResult = await service.sendVoice(message: makeStoredVoiceMessage(), upload: upload)
        let videoResult = await service.sendVideo(message: makeStoredVideoMessage(), upload: upload)
        let fileResult = await service.sendFile(message: makeStoredFileMessage(), upload: upload)
        let voiceRequest = await httpClient.lastVoiceRequest
        let videoRequest = await httpClient.lastVideoRequest
        let fileRequest = await httpClient.lastFileRequest

        #expect(voiceResult == .success(MessageSendAck(serverMessageID: "server_media_ack", sequence: 44, serverTime: 1_777_777_744)))
        #expect(videoResult == .success(MessageSendAck(serverMessageID: "server_media_ack", sequence: 44, serverTime: 1_777_777_744)))
        #expect(fileResult == .success(MessageSendAck(serverMessageID: "server_media_ack", sequence: 44, serverTime: 1_777_777_744)))
        #expect(voiceRequest?.durationMilliseconds == 1_800)
        #expect(voiceRequest?.sizeBytes == 2_048)
        #expect(voiceRequest?.format == "m4a")
        #expect(videoRequest?.durationMilliseconds == 3_600)
        #expect(videoRequest?.width == 640)
        #expect(videoRequest?.height == 360)
        #expect(videoRequest?.sizeBytes == 8_192)
        #expect(fileRequest?.fileName == "report.pdf")
        #expect(fileRequest?.fileExtension == "pdf")
        #expect(fileRequest?.sizeBytes == 16_384)
    }

    @Test func serverMessageSendServiceMapsMediaTransportFailuresToSendFailures() async throws {
        let message = makeStoredImageMessage()
        let upload = MediaUploadAck(mediaID: "image_media", cdnURL: "https://cdn.example/image.png", md5: nil)

        let offlineResult = await ServerMessageSendService(
            httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.offline)
        ).sendImage(message: message, upload: upload)
        let timeoutResult = await ServerMessageSendService(
            httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.timeout)
        ).sendImage(message: message, upload: upload)
        let ackMissingResult = await ServerMessageSendService(
            httpClient: RecordingHTTPClient(error: ChatBridgeHTTPError.ackMissing)
        ).sendImage(message: message, upload: upload)
        let missingURLResult = await ServerMessageSendService(
            httpClient: RecordingHTTPClient()
        ).sendImage(message: message, upload: MediaUploadAck(mediaID: "image_media", cdnURL: "  ", md5: nil))

        #expect(offlineResult == .failure(.offline))
        #expect(timeoutResult == .failure(.timeout))
        #expect(ackMissingResult == .failure(.ackMissing))
        #expect(missingURLResult == .failure(.ackMissing))
    }

    @Test func serverMessageSendServiceRejectsMismatchedStoredMessageContent() async throws {
        let service = ServerMessageSendService(httpClient: RecordingHTTPClient())
        let textMessage = makeStoredTextMessage()
        let imageMessage = makeStoredImageMessage()
        let upload = MediaUploadAck(mediaID: "image_media", cdnURL: "https://cdn.example/image.png", md5: nil)

        let textAsImage = await service.sendImage(message: textMessage, upload: upload)
        let imageAsText = await service.sendText(message: imageMessage)

        #expect(textAsImage == .failure(.ackMissing))
        #expect(imageAsText == .failure(.ackMissing))
    }

    @Test func tokenRefreshingHTTPClientRefreshesAfterUnauthorizedAndRetriesWithUpdatedToken() async throws {
        let tokenBox = TokenBox(token: "expired_token")
        let httpClient = ExpiringTextHTTPClient(
            tokenProvider: {
                await tokenBox.token
            },
            response: ServerTextMessageSendResponse(
                serverMessageID: "refreshed_ack",
                sequence: 77,
                serverTime: 1_777_777_077
            )
        )
        let refreshingClient = TokenRefreshingHTTPClient(httpClient: httpClient) {
            await tokenBox.updateToken("fresh_token")
            return "fresh_token"
        }
        let service = ServerMessageSendService(httpClient: refreshingClient)

        let result = await service.sendText(message: makeStoredTextMessage(clientMessageID: "refresh_client"))

        #expect(result == .success(MessageSendAck(serverMessageID: "refreshed_ack", sequence: 77, serverTime: 1_777_777_077)))
        #expect(await httpClient.textSendCallCount == 2)
        #expect(await httpClient.observedTokens == ["expired_token", "fresh_token"])
    }

    @Test func tokenRefreshingHTTPClientDoesNotRefreshNonUnauthorizedFailures() async throws {
        let httpClient = ExpiringTextHTTPClient(error: ChatBridgeHTTPError.timeout)
        let refreshCallCount = Counter()
        let refreshingClient = TokenRefreshingHTTPClient(httpClient: httpClient) {
            await refreshCallCount.increment()
            return "fresh_token"
        }
        let service = ServerMessageSendService(httpClient: refreshingClient)

        let result = await service.sendText(message: makeStoredTextMessage())

        #expect(result == .failure(.timeout))
        #expect(await refreshCallCount.value == 0)
        #expect(await httpClient.textSendCallCount == 1)
    }

    @Test func tokenRefreshingHTTPClientRefreshesMediaSendAfterUnauthorized() async throws {
        let tokenBox = TokenBox(token: "expired_token")
        let httpClient = ExpiringTextHTTPClient(
            tokenProvider: {
                await tokenBox.token
            },
            response: ServerTextMessageSendResponse(
                serverMessageID: "refreshed_media_ack",
                sequence: 78,
                serverTime: 1_777_777_078
            )
        )
        let refreshingClient = TokenRefreshingHTTPClient(httpClient: httpClient) {
            await tokenBox.updateToken("fresh_token")
            return "fresh_token"
        }
        let service = ServerMessageSendService(httpClient: refreshingClient)

        let result = await service.sendImage(
            message: makeStoredImageMessage(clientMessageID: "refresh_image_client"),
            upload: MediaUploadAck(mediaID: "refresh_image_media", cdnURL: "https://cdn.example/refresh.png", md5: nil)
        )

        #expect(result == .success(MessageSendAck(serverMessageID: "refreshed_media_ack", sequence: 78, serverTime: 1_777_777_078)))
        #expect(await httpClient.mediaSendCallCount == 2)
        #expect(await httpClient.observedTokens == ["expired_token", "fresh_token"])
    }
}

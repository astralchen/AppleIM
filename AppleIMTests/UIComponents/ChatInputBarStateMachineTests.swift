import Testing
import UIKit

@testable import AppleIM

extension AppleIMTests {
    @MainActor
    @Test func chatInputBarStateMachineStartsWithVoiceAction() {
        let machine = ChatInputBarStateMachine()

        #expect(machine.renderState.panel == .keyboard)
        #expect(machine.renderState.trailingAction == .recordVoice(isEnabled: true))
        #expect(machine.renderState.isTextEditable == true)
    }

    @MainActor
    @Test func chatInputBarStateMachineUsesSendActionForText() {
        var machine = ChatInputBarStateMachine()

        let transition = machine.reduce(.setText(" hello "))

        #expect(transition.renderState.text == " hello ")
        #expect(transition.renderState.trailingAction == .send(isEnabled: true))
        #expect(machine.renderState.trailingAction == .send(isEnabled: true))
    }

    @MainActor
    @Test func chatInputBarStateMachineBlocksSendWhileAttachmentLoads() {
        var machine = ChatInputBarStateMachine()

        machine.reduce(.setAttachments([
            ChatPendingAttachmentPreviewItem(
                id: "video-loading",
                image: nil,
                title: "Preparing video",
                durationText: "0:03",
                isVideo: true,
                isLoading: true
            )
        ]))

        #expect(machine.renderState.trailingAction == .recordVoice(isEnabled: false))
        #expect(machine.reduce(.sendComposition).action == nil)
    }

    @MainActor
    @Test func chatInputBarStateMachineAllowsReadyAttachmentSend() {
        var machine = ChatInputBarStateMachine()

        let transition = machine.reduce(.setAttachments([
            ChatPendingAttachmentPreviewItem(
                id: "photo-ready",
                image: nil,
                title: "Image ready",
                durationText: nil,
                isVideo: false,
                isLoading: false
            )
        ]))

        #expect(transition.renderState.trailingAction == .send(isEnabled: true))
        #expect(machine.reduce(.sendComposition).action == .send(""))
        #expect(machine.renderState.attachments.isEmpty)
    }

    @MainActor
    @Test func chatInputBarStateMachineRecordingBlocksEditingAndPanels() {
        var machine = ChatInputBarStateMachine()
        let recording = VoiceRecordingState(
            isRecording: true,
            isCanceling: false,
            elapsedMilliseconds: 4_200,
            averagePowerLevel: 0.5,
            hintText: "Release to preview"
        )

        machine.reduce(.setVoiceRecording(recording))
        let panelTransition = machine.reduce(.showPanel(.emoji))

        #expect(machine.renderState.voicePresentation == .recording(recording))
        #expect(machine.renderState.isTextEditable == false)
        #expect(machine.renderState.trailingAction == .hidden)
        #expect(panelTransition.renderState.panel == .keyboard)
    }

    @MainActor
    @Test func chatInputBarStateMachineVoicePreviewBlocksTextSendButEmitsVoiceActions() {
        var machine = ChatInputBarStateMachine()
        let preview = ChatVoicePreviewState(
            durationMilliseconds: 7_000,
            isPlaying: true,
            playbackProgress: 0.4,
            playbackElapsedMilliseconds: 2_800
        )

        machine.reduce(.setText("ignored while previewing"))
        machine.reduce(.setVoicePreview(preview))

        #expect(machine.renderState.voicePresentation == .preview(preview))
        #expect(machine.renderState.isTextEditable == false)
        #expect(machine.renderState.trailingAction == .hidden)
        #expect(machine.reduce(.sendComposition).action == nil)
        #expect(machine.reduce(.voicePreviewPlayToggle).action == .voicePreviewPlayToggle)
        #expect(machine.reduce(.voicePreviewSend).action == .voicePreviewSend)
    }

    @MainActor
    @Test func chatInputBarStateMachinePanelTransitionsTrackAnimationIntent() {
        var machine = ChatInputBarStateMachine()

        let photoTransition = machine.reduce(.showPanel(.photoLibrary))
        let keyboardTransition = machine.reduce(.showPanel(.keyboard))

        #expect(photoTransition.renderState.panel == .photoLibrary)
        #expect(photoTransition.animation == .panelTransition(from: .keyboard, to: .photoLibrary))
        #expect(keyboardTransition.renderState.panel == .keyboard)
        #expect(keyboardTransition.animation == .panelTransition(from: .photoLibrary, to: .keyboard))
    }
}

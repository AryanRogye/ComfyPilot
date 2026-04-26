//
//  ChatSidebar.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/25/26.
//

import SwiftUI
import ComfyPilotUI

struct ChatSidebar: View {
    
    @Bindable var vm: ChatViewModel
    @Binding var sendingMessage: Bool
    
    var body: some View {
        VStack {
            ChatListView(chatVM: vm)
                .safeAreaInset(edge: .bottom) {
                    ChatInputBar(sendingMessage: $sendingMessage) { text in
                        vm.send(text)
                    }
                }
        }
        .frame(minWidth: 320)
    }
}


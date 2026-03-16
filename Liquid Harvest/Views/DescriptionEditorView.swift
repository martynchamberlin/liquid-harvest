//
//  DescriptionEditorView.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import SwiftUI

struct DescriptionEditorView: View {
    @ObservedObject var timerViewModel: TimerViewModel
    @State private var editingDescription: String = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                TextField("Enter description...", text: $editingDescription, axis: .vertical)
                    .font(.title3)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .focused($isFocused)
                    .lineLimit(1...)
                    .onSubmit {
                        saveDescription()
                    }
                    .onTapGesture {
                        // Allow manual focus/selection
                        isFocused = true
                    }

                HStack {
                    Button("Cancel") {
                        cancelEditing()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Save") {
                        saveDescription()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(nsColor: .textBackgroundColor))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .labelColor))
                    .cornerRadius(6)
                }
            } else {
                Button(action: {
                    startEditing()
                }) {
                    HStack {
                        Text(timerViewModel.description.isEmpty ? "Add description..." : timerViewModel.description)
                            .font(.title3)
                            .foregroundStyle(timerViewModel.description.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)

                        if !timerViewModel.description.isEmpty {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            editingDescription = timerViewModel.description
        }
        .onChange(of: timerViewModel.description) { newValue in
            if !isEditing {
                editingDescription = newValue
            }
        }
    }

    private func startEditing() {
        editingDescription = timerViewModel.description
        isEditing = true
        // Don't auto-focus to avoid selecting all text
        // User can click into the field to edit
    }

    private func cancelEditing() {
        editingDescription = timerViewModel.description
        isEditing = false
        isFocused = false
    }

    private func saveDescription() {
        // Use explicit Swift concurrency Task to avoid conflict with Harvest Task model
        _Concurrency.Task {
            await timerViewModel.updateDescription(editingDescription)
            isEditing = false
            isFocused = false
        }
    }
}

#Preview {
    DescriptionEditorView(timerViewModel: TimerViewModel())
        .padding()
}

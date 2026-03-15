import SwiftUI

struct ExportWizardView: View {
    @Environment(ExportWizardStore.self) private var wizardStore
    @Environment(UserDataStore.self) private var userDataStore
    @Environment(UIStateStore.self) private var uiStateStore
    @Environment(BibleStore.self) private var bibleStore

    var onDismiss: (() -> Void)?

    var body: some View {
        @Bindable var store = wizardStore

        VStack(spacing: 0) {
            // Header with cancel button
            HStack {
                Button {
                    wizardStore.cancelExport()
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                        onDismiss?()
                    }
                } label: {
                    Label("Back to Settings", systemImage: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // Step indicator
            ExportWizardStepIndicator(currentStep: store.currentStep)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)

            Divider()

            // Step content
            Group {
                switch store.currentStep {
                case .contentSelection:
                    ContentSelectionStep()
                case .ordering:
                    OrderingStep()
                case .formatting:
                    FormattingStep()
                case .export:
                    ExportStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.spring(duration: 0.35, bounce: 0.15), value: store.currentStep)

            Divider()

            // Navigation buttons
            ExportWizardNavBar()
                .padding(16)
        }
        .onAppear {
            wizardStore.loadItems(from: userDataStore)
            wizardStore.initializeFonts(from: uiStateStore)
            if let activeModule = bibleStore.modules.first {
                wizardStore.initializeModules(activeModuleId: activeModule.id)
            }
        }
    }
}

// MARK: - Step Indicator

struct ExportWizardStepIndicator: View {
    let currentStep: ExportWizardStep

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ExportWizardStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 24, height: 24)
                        if step.rawValue < currentStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(step.rawValue <= currentStep.rawValue ? .white : .secondary)
                        }
                    }
                    Text(step.title)
                        .font(.caption)
                        .foregroundStyle(step == currentStep ? .primary : .secondary)
                        .lineLimit(1)
                }

                if step != ExportWizardStep.allCases.last {
                    Spacer(minLength: 4)
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 1.5)
                    Spacer(minLength: 4)
                }
            }
        }
    }
}

// MARK: - Navigation Bar

struct ExportWizardNavBar: View {
    @Environment(ExportWizardStore.self) private var wizardStore

    var body: some View {
        HStack {
            if wizardStore.currentStep.canGoBack {
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                        wizardStore.goBack()
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Text("\(wizardStore.selectedItemIds.count) items selected")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if wizardStore.currentStep.canGoNext {
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                        wizardStore.goNext()
                    }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!wizardStore.canProceedFromCurrentStep)
            }
        }
    }
}

// Step views are defined in ExportStepViews.swift

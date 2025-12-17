//
//  LoginView.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "clock.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Liquid Harvest")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Time tracking with style")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.red.opacity(0.1))
                    .cornerRadius(8)
            }

            Button(action: {
                viewModel.startLogin()
            }) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Log in with Harvest")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(Color(nsColor: .textBackgroundColor))
                .background(Color(nsColor: .labelColor))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .padding(.horizontal, 40)
        }
        .padding(40)
        .frame(maxWidth: 400, maxHeight: 500)
        .glassEffect()
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthenticationViewModel())
}


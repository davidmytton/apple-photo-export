//
//  PhotoExportApp.swift
//  PhotoExport
//
//  Created by David Mytton on 2025-02-16.
//

import SwiftUI
import Photos

@main
struct PhotoExportApp: App {
    @State private var hasPermission = PHPhotoLibrary.authorizationStatus() == .authorized ||
    PHPhotoLibrary.authorizationStatus() == .limited
    
    var body: some Scene {
        WindowGroup {
            if hasPermission {
                ContentView()
            } else {
                PermissionView(hasPermission: $hasPermission)
            }
        }
    }
}

struct PermissionView: View {
    @Binding var hasPermission: Bool
    
    var body: some View {
        VStack {
            Text("Photo Access Required")
                .font(.title)
                .padding()
            Text("To export your photos, we need access to your photo library.")
                .multilineTextAlignment(.center)
                .padding()
            Button("Grant Access") {
                requestPhotoAccess { granted in
                    hasPermission = granted
                }
            }
            .padding()
        }
        .onAppear {
            requestPhotoAccess { granted in
                hasPermission = granted
            }
        }
    }
}

func requestPhotoAccess(completion: @escaping (Bool) -> Void) {
    let status = PHPhotoLibrary.authorizationStatus()
    
    switch status {
    case .authorized, .limited:
        completion(true)
    case .notDetermined:
        PHPhotoLibrary.requestAuthorization { newStatus in
            DispatchQueue.main.async {
                completion(newStatus == .authorized || newStatus == .limited)
            }
        }
    default:
        completion(false)
    }
}

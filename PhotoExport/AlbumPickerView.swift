//
//  AlbumPickerView.swift
//  PhotoExport
//
//  Created by David Mytton on 2025-02-16.
//

import SwiftUI
import Photos
import AppKit


struct AlbumPickerView: View {
    @ObservedObject var albumLibrary = AlbumLibraryManager()
    
    // Export manager
    private let exportManager = PhotoExportManager()
    
    // MARK: - State Properties
    @State private var selectedAlbumIDs: Set<String> = []
    @State private var exportDirectory: URL?
    @State private var isExporting = false
    @State private var exportProgressMessage = ""
    
    @State private var totalAssetCount = 0
    @State private var processedAssetCount = 0
    @State private var overallProgress: Double = 0.0
    @State private var showProgressView = false
    @State private var shouldCancel = false
    
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    var body: some View {
        VStack(alignment: .leading) {
            if albumLibrary.isLoading {
                HStack {
                    Text("Loading albums")
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }.padding(.top, 8)
            } else {
                // MARK: Directory Selection
                VStack(alignment: .leading) {
                    Text("Select export destination")
                        .font(.title2)
                        .padding(.bottom, 8)
                    
                    HStack {
                        Button("Choose destination") {
                            if let directory = chooseDirectory() {
                                exportDirectory = directory
                            }
                        }
                        .accessibilityLabel("Choose destination")
                        .accessibilityHint("Opens a dialog to choose a folder for export")
                        
                        if let directory = exportDirectory {
                            Text("Directory: \(directory.path)")
                                .lineLimit(1)
                                .accessibilityLabel("Selected export directory: \(directory.path)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
              
                
                // MARK: Album List
                Text("Select albums to export")
                    .font(.title2)
                    .padding(.vertical, 8)
                
                List(selection: $selectedAlbumIDs) {
                    ForEach(albumLibrary.albums, id: \.localIdentifier) { album in
                        HStack {
                            Text(album.localizedTitle ?? "Unknown Album")
                                .font(.body)
                            Spacer()
                            Text("\(fetchAssetCount(for: album))")
                                .foregroundColor(.secondary)
                                .accessibilityLabel("\(fetchAssetCount(for: album)) photos")
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(PlainListStyle())
                .accessibilityLabel("Album List")
                
                Text("Export")
                    .font(.title2)
                    .padding(.vertical, 8)
                
                // MARK: Export Action Buttons
                HStack {
                    Button("Export Selected Albums") {
                        guard let directory = exportDirectory else { return }
                        exportSelectedAlbums(to: directory)
                    }
                    .disabled(selectedAlbumIDs.isEmpty || exportDirectory == nil || isExporting)
                    .accessibilityLabel("Export Selected Albums")
                    
                    Button("Export All Photos") {
                        guard let directory = exportDirectory else { return }
                        exportAllPhotos(to: directory)
                    }
                    .disabled(exportDirectory == nil || isExporting)
                    .accessibilityLabel("Export All Photos")
                }
                
                // MARK: Progress View
                if showProgressView {
                    VStack(alignment: .leading) {
                        
                        
                        ProgressView("Exporting...", value: overallProgress, total: 1.0)
                            .padding(.vertical)
                        
                        Text(statusText())
                            .font(.caption)
                            .padding(.bottom, 8)
                        
                        HStack {
                            if isExporting {
                                Button("Cancel") {
                                    shouldCancel = true
                                    exportProgressMessage = "Cancelling export..."
                                }
                                .padding(.trailing, 8)
                                .padding(.bottom, 8)
                            }
                            Button("Dismiss") {
                                resetProgressView()
                            }
                            .disabled(isExporting)
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.windowBackgroundColor)))
                    .padding()
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .alert(isPresented: $showErrorAlert) {
            Alert(title: Text("Error"),
                  message: Text(errorMessage ?? "Unknown error"),
                  dismissButton: .default(Text("OK")))
        }
    }
}

// MARK: - Preview

struct AlbumPickerView_Previews: PreviewProvider {
    static var previews: some View {
        AlbumPickerView()
    }
}

// MARK: - Extension: AlbumPickerView Logic

// MARK: - Extension: Export Methods

extension AlbumPickerView {
    func exportSelectedAlbums(to directory: URL) {
        guard directory.startAccessingSecurityScopedResource() else {
            errorMessage = "Could not access directory security scope."
            showErrorAlert = true
            return
        }
        defer { directory.stopAccessingSecurityScopedResource() }
        
        isExporting = true
        showProgressView = true
        exportProgressMessage = "Starting export..."
        shouldCancel = false
        
        let selectedAlbums = albumLibrary.albums.filter { selectedAlbumIDs.contains($0.localIdentifier) }
        
        exportManager.exportSelectedAlbums(
            albums: selectedAlbums,
            to: directory,
            progressHandler: { processed, total, message in
                processedAssetCount = processed
                totalAssetCount = total
                overallProgress = Double(processed) / Double(total)
                exportProgressMessage = message
            },
            completion: { cancelled, processed, total in
                isExporting = false
                if cancelled {
                    exportProgressMessage = "Export cancelled. \(processed) of \(total) assets backed up."
                } else {
                    exportProgressMessage = "Export completed."
                }
            },
            errorHandler: { errorMsg in
                errorMessage = errorMsg
                showErrorAlert = true
            },
            shouldCancel: { shouldCancel }
        )
    }
    
    func exportAllPhotos(to directory: URL) {
        guard directory.startAccessingSecurityScopedResource() else {
            errorMessage = "Could not access directory security scope."
            showErrorAlert = true
            return
        }
        defer { directory.stopAccessingSecurityScopedResource() }
        
        isExporting = true
        showProgressView = true
        exportProgressMessage = "Starting organized export of all photos..."
        shouldCancel = false
        
        exportManager.exportAllPhotos(
            to: directory,
            progressHandler: { processed, total, message in
                processedAssetCount = processed
                totalAssetCount = total
                overallProgress = Double(processed) / Double(total)
                exportProgressMessage = message
            },
            completion: { cancelled, processed, total in
                isExporting = false
                if cancelled {
                    exportProgressMessage = "Export cancelled. \(processed) of \(total) assets backed up."
                } else {
                    exportProgressMessage = "Organized export of all photos completed."
                }
            },
            errorHandler: { errorMsg in
                errorMessage = errorMsg
                showErrorAlert = true
            },
            shouldCancel: { shouldCancel }
        )
    }
    
    /// Presents an NSOpenPanel to choose a export directory.
    func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Export Directory"
        return panel.runModal() == .OK ? panel.url : nil
    }
    
    /// Creates a concise status message based on export state.
    func statusText() -> String {
        // Convert the processed and total counts to localized strings with comma separators.
        let processedStr = localizedNumberString(for: processedAssetCount)
        let totalStr = localizedNumberString(for: totalAssetCount)
        
        if shouldCancel && !isExporting {
            return "Export cancelled at \(processedStr) of \(totalStr)."
        } else if !isExporting {
            return "Export complete: \(processedStr) of \(totalStr) assets."
        } else {
            return "Exporting \(processedStr) of \(totalStr) assets..."
        }
    }
    
    /// Converts an Int into a localized string (e.g. adds comma separators).
    private func localizedNumberString(for number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    /// Resets the progress view state.
    func resetProgressView() {
        showProgressView = false
        totalAssetCount = 0
        processedAssetCount = 0
        overallProgress = 0.0
        exportProgressMessage = ""
        shouldCancel = false
    }
    
    /// Returns the number of assets in the given album.
    func fetchAssetCount(for album: PHAssetCollection) -> Int {
        let fetchResult = PHAsset.fetchAssets(in: album, options: nil)
        return fetchResult.count
    }
}

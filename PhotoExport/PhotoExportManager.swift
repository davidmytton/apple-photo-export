//
//  PhotoBackupManager.swift
//  PhotoExport
//
//  Created by David Mytton on 2025-02-16.
//


//
//  PhotoBackupManager.swift
//  photosoexport
//
//  Created by David Mytton on 2025-02-16.
//


import Photos
import Foundation

/// Handles the logic for backing up photos from PhotoKit to a local directory.
class PhotoExportManager {
    
    private let resourceManager = PHAssetResourceManager.default()
    
    /// Exports the specified albums to the chosen directory.
    ///
    /// - Parameters:
    ///   - albums: A list of PHAssetCollections to back up.
    ///   - directory: The local file system directory where files should be written.
    ///   - progressHandler: Closure called when each asset is processed, receiving:
    ///       * processedCount: Number of assets processed so far.
    ///       * totalCount: Total number of assets being processed.
    ///       * message: A status message you can display in the UI.
    ///   - completion: Closure called when the export finishes or is cancelled,
    ///       receiving a boolean indicating whether it was cancelled, plus final processed/total counts.
    ///   - errorHandler: Closure called if an error occurs (e.g. file creation error).
    ///   - shouldCancel: A closure you can invoke to check whether the user has requested cancellation.
    func exportSelectedAlbums(
        albums: [PHAssetCollection],
        to directory: URL,
        progressHandler: @escaping (_ processedCount: Int, _ totalCount: Int, _ message: String) -> Void,
        completion: @escaping (_ cancelled: Bool, _ processedCount: Int, _ totalCount: Int) -> Void,
        errorHandler: @escaping (_ errorMessage: String) -> Void,
        shouldCancel: @escaping () -> Bool
    ) {
        // 1) Calculate total number of assets.
        let totalAssetCount = albums.reduce(0) { count, album in
            count + PHAsset.fetchAssets(in: album, options: nil).count
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var processedCount = 0
            for album in albums {
                if shouldCancel() { break }
                
                let albumName = album.localizedTitle ?? "UnknownAlbum"
                let albumDirectory = directory.appendingPathComponent(albumName)
                
                // Create album subdirectory if needed.
                do {
                    try FileManager.default.createDirectory(at: albumDirectory, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    errorHandler("Failed to create album directory '\(albumName)': \(error.localizedDescription)")
                    continue
                }
                
                let fetchResult = PHAsset.fetchAssets(in: album, options: nil)
                let assets = fetchResult.objects(at: IndexSet(integersIn: 0..<fetchResult.count))
                
                for asset in assets {
                    if shouldCancel() { break }
                    
                    guard let resource = self.bestResource(for: asset) else { continue }
                    let fileURL = albumDirectory.appendingPathComponent(resource.originalFilename)
                    
                    let options = PHAssetResourceRequestOptions()
                    options.isNetworkAccessAllowed = true
                    
                    let semaphore = DispatchSemaphore(value: 0)
                    self.resourceManager.writeData(for: resource, toFile: fileURL, options: options) { error in
                        if let error = error {
                            errorHandler("Error saving \(resource.originalFilename): \(error.localizedDescription)")
                        }
                        semaphore.signal()
                    }
                    semaphore.wait()
                    
                    processedCount += 1
                    let message = "Exported \(resource.originalFilename) from \(albumName)"
                    
                    DispatchQueue.main.async {
                        progressHandler(processedCount, totalAssetCount, message)
                    }
                }
            }
            
            let cancelled = shouldCancel()
            DispatchQueue.main.async {
                completion(cancelled, processedCount, totalAssetCount)
            }
        }
    }
    
    /// Backs up all photos in the library to the specified directory, organizing them by album membership.
    func exportAllPhotos(
        to directory: URL,
        progressHandler: @escaping (_ processedCount: Int, _ totalCount: Int, _ message: String) -> Void,
        completion: @escaping (_ cancelled: Bool, _ processedCount: Int, _ totalCount: Int) -> Void,
        errorHandler: @escaping (_ errorMessage: String) -> Void,
        shouldCancel: @escaping () -> Bool
    ) {
        let fetchOptions = PHFetchOptions()
        let allPhotos = PHAsset.fetchAssets(with: fetchOptions)
        let assets = allPhotos.objects(at: IndexSet(integersIn: 0..<allPhotos.count))
        
        let totalAssetCount = assets.count
        
        DispatchQueue.global(qos: .userInitiated).async {
            var processedCount = 0
            for asset in assets {
                if shouldCancel() { break }
                
                // Identify album membership (user-created albums).
                let collectionsResult = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
                let albumArray = collectionsResult.objects(at: IndexSet(integersIn: 0..<collectionsResult.count))
                let validAlbums = albumArray.filter { !($0.localizedTitle?.isEmpty ?? true) }
                let folderName = validAlbums.first?.localizedTitle ?? "Unorganized"
                
                let targetDirectory = directory.appendingPathComponent(folderName)
                do {
                    try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    errorHandler("Failed to create directory '\(folderName)': \(error.localizedDescription)")
                    continue
                }
                
                guard let resource = self.bestResource(for: asset) else { continue }
                let fileURL = targetDirectory.appendingPathComponent(resource.originalFilename)
                
                // Skip if file already exists
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    processedCount += 1
                    let skipMessage = "Skipped existing \(resource.originalFilename) in \(folderName)"
                    DispatchQueue.main.async {
                        progressHandler(processedCount, totalAssetCount, skipMessage)
                    }
                    continue
                }
                
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true
                
                let semaphore = DispatchSemaphore(value: 0)
                self.resourceManager.writeData(for: resource, toFile: fileURL, options: options) { error in
                    if let error = error {
                        errorHandler("Error saving \(resource.originalFilename): \(error.localizedDescription)")
                    }
                    semaphore.signal()
                }
                semaphore.wait()
                
                processedCount += 1
                let message = "Exported \(resource.originalFilename) into \(folderName)"
                
                DispatchQueue.main.async {
                    progressHandler(processedCount, totalAssetCount, message)
                }
            }
            
            let cancelled = shouldCancel()
            DispatchQueue.main.async {
                completion(cancelled, processedCount, totalAssetCount)
            }
        }
    }
    
    /// Returns the best resource for an asset, preferring full-size photos or videos.
    private func bestResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        if let fullSize = resources.first(where: { $0.type == .fullSizePhoto || $0.type == .fullSizeVideo }) {
            return fullSize
        }
        return resources.first(where: { $0.type == .photo || $0.type == .video })
    }
}

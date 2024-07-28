# Nice Downloader Library

This Dart library provides a comprehensive solution for managing file downloads in your Flutter applications. It offers features like pausing, resuming, cancelingdownloads, tracking progress, and handling network connectivity.


https://github.com/user-attachments/assets/e2c462d3-dcfa-4811-9dea-8f729b667fb3


## Key Features:

* **Pause/Resume:** Easily pause and resume downloads.
* **Cancel:** Cancel ongoing downloads and delete the file.
* **Progress Tracking:** Monitor download progress with detailed information (bytes downloaded, total bytes, speed).
* **Network Handling:**Checks and waits for internet connectivity.
* **File Existence Check:** Resumes downloads if the file already exists.
* **Customizable File Names:** Optionally provide custom file names.
* **Download Manager:** Manage multiple downloads efficiently.

## Usage:

1. **Create a `DownloadManager` instance:**
```dart 
DownloadManager downloadManager = DownloadManager();
```
2. **Create a `Downloader` using `downloadManager`:**
```dart
Downloader downloader = await downloadManager.createDownload(  url: 'your_download_url',  downloadPath: 'path_to_save_file',  fileName: 'optional_file_name' ) ; 
```
3. **Listen for download progress updates:**
```dart
late StreamSubscription<DownloaderData> listener;
listener = downloader.listen
((DownloaderData data) { 
  // Update UI or perform actions based on download data print('Downloaded: ${data.downloadedBytes}  / ${data.totalBytes}') ;  
});
  
```

4. **Initialize and start the download:**
```dart
await downloader.initDownload();  // Check for existing downloads 
await downloader.start();
```


```dart
    DownloadManager downloadManager = DownloadManager();
    Downloader downloader = await downloadManager.createDownload(
        url:
            'https://sample-videos.com/video321/mp4/720/big_buck_bunny_720p_20mb.mp4',
        downloadPath: (await getDownloadsDirectory())!.path,
        fileName: "test");

    late StreamSubscription<DownloaderData> listener;
    listener = downloader.listen((DownloaderData data) {
      print(data.downloadedBytes.formatSize.size);
      print(data.downloadedBytes.formatSize.type);

      print(data.downloadSpeed?.speed);
      print(data.downloadSpeed?.type);

      print(data.downloadStatus);
      print(data.totalBytes.formatSize.size);

      if(data.downloadStatus == DOWNLOAD_STATUS.COMPLETED){
        // if you do not want this Downloader any more you have to
        // close the listener and dispose the downloader
        listener.cancel();
        downloader.dispose();
      }
      
    });

    await downloader.initDownload();
    await downloader.start();
```

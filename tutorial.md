# Street Scan App Tutorial

This is a user-focused walkthrough for using the app, from the first launch to reviewing and uploading sessions.

## 1) First Launch and Permissions

1. Open the app.
2. Grant permissions when prompted:
	- Camera (required for live detection)
	- Location (required for maps and proximity alerts)
	- Storage (required for saving snapshots)

If you deny a permission, you can enable it later in system settings.

## 2) Start a Live Detection Session

1. From the main screen, open the live detection view.
2. The camera preview should appear within a few seconds.
3. As potholes are detected, bounding boxes will appear in real time.

Tips:
- Keep the phone steady and aim toward the road surface.
- If detection feels slow, reduce the processing interval in the settings panel.

## 3) Automatic Snapshot Capture

When detections occur, the app saves snapshots automatically. These are attached to your current session and stored locally so you can review them offline.

You can control snapshot frequency in the detection settings.

## 4) Review Your Session

1. Open the session review screen.
2. Scroll through captures, locations, and performance stats.
3. Select any items you want to delete, then tap the delete action.

The mini map shows the route path and detected locations. Tap into fullscreen mode for more detail.

## 5) Explore the Map

1. Open the map view.
2. Toggle between local, global, or combined data sources.
3. Use the heatmap toggle to visualize high density areas.

The blue radius ring shows the proximity alert range.

## 6) Upload Sessions

1. Open the Upload Manager.
2. Select local sessions you want to upload.
3. Tap Review Selected to confirm.
4. The app uploads session metadata to Firestore and images to Cloudinary.

Progress updates appear in the upload list and via notifications.

## 7) Proximity Alerts

If you are near potholes (local or server data), you will receive a notification while the app is running. The alert updates as you move.

## 8) Common Issues

- Camera does not open: check camera permissions and restart the app.
- No map tiles: verify your MapTiler key and network connection.
- Uploads stuck: confirm Cloudinary credentials and connectivity.

## 9) Glossary

- Session: a single detection run with captured entries and GPS history
- Entry: one pothole capture with location, time, and image
- Heatmap: density visualization of detected potholes

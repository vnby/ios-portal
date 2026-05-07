<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./static/portal-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="./static/portal.png">
  <img src="./static/portal.png"  width="full">
</picture>

[![GitHub stars](https://img.shields.io/github/stars/droidrun/ios-portal?style=social)](https://github.com/droidrun/ios-portal/stargazers)
[![Discord](https://img.shields.io/discord/1360219330318696488?color=7289DA&label=Discord&logo=discord&logoColor=white)](https://discord.gg/ZZbKEZZkwK)
[![Documentation](https://img.shields.io/badge/Documentation-📕-blue)](https://docs.droidrun.ai)
[![Twitter Follow](https://img.shields.io/twitter/follow/droid_run?style=social)](https://x.com/droid_run)


A comprehensive iOS automation portal that provides HTTP API access to iOS device UI state extraction and automated interactions.

## Overview

The Droidrun iOS Portal is a specialized iOS application that runs UI tests to expose device automation capabilities through a RESTful HTTP API. It consists of two main components:

1. **Portal App** (`droidrun-ios-portal`): A minimal SwiftUI application that serves as the host
2. **Portal Server** (`droidrun-ios-portalUITests`): XCTest-based HTTP server providing automation APIs

## Architecture

The portal leverages iOS XCTest framework and XCUITest capabilities to:
- Extract UI state information (accessibility trees, screenshots)
- Perform automated interactions (taps, swipes, text input)
- Launch and manage applications
- Handle device-level inputs

### Key Components

- **DroidrunPortalServer**: XCTest class that runs an HTTP server on port 6643
- **DroidrunPortalHandler**: HTTP route handler defining the REST API endpoints
- **DroidrunPortalTools**: Core automation engine implementing device interactions
- **AccessibilityTree**: UI state extraction and compression utilities

## Local Setup with Mobilerun

Mobilerun does not install the iOS Portal automatically. `mobilerun setup` is
for Android devices only. For iOS, first run this Xcode UI test server, then
point Mobilerun at the local HTTP port.

### 1. Install Mobilerun in a virtual environment

```bash
mkdir mobilerun-ios-test
cd mobilerun-ios-test

uv venv .venv
source .venv/bin/activate
uv pip install mobilerun

mobilerun configure

# Return to this repository before running the Xcode commands below.
cd ..
```

Alternatively, configure your LLM provider with environment variables and pass
the matching provider/model flags when you run Mobilerun. For example, with
OpenAI:

```bash
export OPENAI_API_KEY=your-api-key

# Later, add these flags to the `mobilerun run` examples:
#   --provider OpenAIResponses --model gpt-5.4
```

### 2. Prepare Xcode signing

Open this project:

```bash
open droidrun-ios-portal.xcodeproj
```

In Xcode, select each target and update **Signing & Capabilities**:

- **Droidrun Portal**
  - Enable **Automatically manage signing**
  - Set your Apple Developer **Team**
  - Change the bundle identifier to something unique, for example
    `ai.yourname.droidrun-ios-portal`
- **Droidrun Server**
  - Enable **Automatically manage signing**
  - Set the same Apple Developer **Team**
  - Change the bundle identifier to something unique, for example
    `ai.yourname.droidrun-ios-portal-uitests`

The default bundle identifiers belong to the Droidrun team, so normal local
development requires changing them.

### 3. Run on a physical iPhone or iPad

Prerequisites:

- Xcode installed and opened at least once
- iOS Developer Mode enabled on the device
- Device connected over USB and trusted by the Mac
- `iproxy`, installed with `brew install libimobiledevice`

Find your device UDID:

```bash
xcrun xctrace list devices
```

Start the portal UI test:

```bash
./device.sh YOUR_DEVICE_UDID
```

Keep the Xcode test session running. The portal stops when the UI test stops.
Look for a log line like:

```text
Portal server listening on port 6643
```

In another terminal, forward a Mac localhost port to the device port:

```bash
iproxy 6643 6643
```

If Xcode says the portal is listening on a different device port, for example
`6644`, forward to that port instead:

```bash
iproxy 6643 6644
```

Verify from the Mac:

```bash
curl http://127.0.0.1:6643/device/date
```

Then run Mobilerun from the virtual environment:

```bash
cd mobilerun-ios-test
source .venv/bin/activate

mobilerun run "take a screenshot" --ios --device http://127.0.0.1:6643
```

Mobilerun also scans `127.0.0.1:6643-6652`, so this usually works after the
portal and forwarding are running:

```bash
mobilerun run "take a screenshot" --ios
```

### 4. Run on the iOS Simulator

The simulator does not need code signing changes for a real device and does
not need `iproxy`.

```bash
xcrun simctl list devices available
./simulator.sh "iPhone 16 Pro"
```

The simulator prints the port it bound, for example:

```text
Portal server listening on port 6643
```

Use that printed port in the health check and explicit `--device` URL. If the
printed port is `6644`, replace `6643` with `6644` below.

```bash
curl http://127.0.0.1:6643/device/date

cd mobilerun-ios-test
source .venv/bin/activate
mobilerun run "take a screenshot" --ios --device http://127.0.0.1:6643
```

You can also omit `--device` and let Mobilerun scan `127.0.0.1:6643-6652`.

### Troubleshooting

#### `iproxy` says `Connection refused`

`iproxy` is working, but nothing is listening on that port inside the iOS
device. Re-run **Product > Test** in Xcode, not just the Play button, and match
the port printed by Xcode:

```text
Portal server listening on port 6644
```

Use:

```bash
iproxy 6643 6644
```

#### Mobilerun cannot find the portal

Check the health endpoint directly:

```bash
curl http://127.0.0.1:6643/device/date
```

If that fails on a physical device, check that the UI test and `iproxy` are
still running. If it fails on simulator, re-run `./simulator.sh`.

## API Reference

### Device Information

#### GET `/device/date`
Returns the current date from the device. Mobilerun uses this as its health
check when discovering the portal.

**Response:**
```json
{
  "date": "2026-05-07T14:03:00.000Z"
}
```

### Vision & State Extraction

#### GET `/state`
Retrieves the current phone state, screen bounds, and compressed accessibility
tree.

**Response:**
```json
{
  "a11y_tree": "Compressed accessibility tree string",
  "phone_state": {
    "currentApp": "Home Screen",
    "packageName": "com.apple.springboard",
    "keyboardVisible": false,
    "isEditable": false,
    "focusedElement": null
  },
  "device_context": {
    "screen_bounds": {
      "width": 430,
      "height": 932
    }
  }
}
```

#### GET `/vision/screenshot`
Captures a screenshot of the current screen.

**Response:** PNG image data (Content-Type: image/png)

### App Management

#### POST `/inputs/launch`
Launches an application by bundle identifier.

**Request Body:**
```json
{
  "bundleIdentifier": "com.example.app"
}
```

**Response:**
```json
{
  "message": "opened com.example.app"
}
```

### Gesture Automation

#### POST `/gestures/tap`
Performs tap gestures on screen coordinates.

**Request Body:**
```json
{
  "rect": "{{x,y},{width,height}}",
  "count": 1,
  "longPress": false
}
```

**Response:**
```json
{
  "message": "tapped element"
}
```

#### POST `/gestures/swipe`
Performs swipe gestures between specified coordinates.

**Request Body:**
```json
{
  "x1": 100.0,
  "y1": 700.0,
  "x2": 100.0,
  "y2": 200.0,
  "durationMs": 300
}
```

**Response:**
```json
{
  "message": "swiped"
}
```

### Input Automation

#### POST `/inputs/type`
Enters text into a focused input field.

**Request Body:**
```json
{
  "rect": "{{x,y},{width,height}}",
  "text": "Hello World",
  "clear": false
}
```

**Response:**
```json
{
  "message": "entered text"
}
```

#### POST `/inputs/key`
Presses device hardware keys.

**Request Body:**
```json
{
  "key": 1
}
```

**Supported keys:**
- `1`: Home button
- `2`: Volume up (physical devices only)
- `3`: Volume down (physical devices only)
- `4`: Action button
- `5`: Camera button

**Response:**
```json
{
  "message": "pressed key"
}
```

## Features

### UI State Extraction
- **Accessibility Tree**: Compressed representation of the UI hierarchy with memory addresses removed
- **Screenshots**: PNG format screen captures
- **App State**: Current application context and keyboard status

### Automation Capabilities
- **App Launching**: Launch any installed app by bundle identifier
- **Touch Interactions**: Single taps, double taps, long presses
- **Gesture Recognition**: Swipe gestures in four directions
- **Text Input**: Automated typing with keyboard handling
- **Hardware Keys**: Device button presses

### Smart Features
- **App Management**: Automatic app switching and state management
- **Keyboard Detection**: Intelligent keyboard presence detection
- **Focus Management**: Ensures proper element focus for text input
- **Error Handling**: Comprehensive error reporting and validation

## Usage

### Prerequisites
- iOS device or simulator
- Xcode with XCTest capabilities
- For physical devices, `iproxy` from `libimobiledevice`

### Running the Portal

1. Build and test the portal project on the target iOS device or simulator
2. The XCTest suite starts the HTTP server on port 6643, or the next available port up to 6652
3. The server will continue running until the test session ends
4. For physical devices, forward the port with `iproxy`

### Client Integration

The portal is designed to work with automation agents that can:
- Send HTTP requests to the portal endpoints
- Process accessibility tree data for UI understanding
- Coordinate multiple automation actions
- Handle screenshot analysis for visual verification

### Example Client Usage

```python
import requests

# Health check
response = requests.get('http://127.0.0.1:6643/device/date')
print(response.json())

# Take screenshot
screenshot = requests.get('http://127.0.0.1:6643/vision/screenshot')
with open('screenshot.png', 'wb') as f:
    f.write(screenshot.content)

# Get accessibility tree
state = requests.get('http://127.0.0.1:6643/state').json()
print(state['a11y_tree'])

# Launch app
requests.post('http://127.0.0.1:6643/inputs/launch',
              json={'bundleIdentifier': 'com.apple.mobilesafari'})

# Perform tap
requests.post('http://127.0.0.1:6643/gestures/tap',
              json={'rect': '{{100,200},{50,50}}', 'count': 1})
```

### Mobilerun CLI example

After the portal health check succeeds, use Mobilerun directly:

```bash
cd mobilerun-ios-test
source .venv/bin/activate

mobilerun run "Open Settings and check Wi-Fi" \
  --ios \
  --device http://127.0.0.1:6643
```

You can also pass a provider and model explicitly:

```bash
mobilerun run "Open Instagram and click the search icon" \
  --ios \
  --device http://127.0.0.1:6643 \
  --provider OpenAIResponses \
  --model gpt-5.4
```

### Mobilerun Python example

```python
import asyncio

from mobilerun import MobileAgent
from mobilerun.config_manager import ConfigLoader


async def main() -> None:
    config = ConfigLoader.load()
    config.device.platform = "ios"
    config.device.serial = "http://127.0.0.1:6643"

    agent = MobileAgent(
        goal="Open Settings and check Wi-Fi",
        config=config,
    )
    result = await agent.run()
    print(result)


if __name__ == "__main__":
    asyncio.run(main())
```

## Technical Details

### Dependencies
- **FlyingFox**: HTTP server framework for Swift
- **XCTest**: iOS testing framework for UI automation
- **SwiftUI**: User interface framework

### Server Configuration
- **Port**: 6643 (configurable)
- **Protocol**: HTTP/1.1
- **Content Types**: JSON, PNG images
- **Threading**: Async/await support

### Coordinate System
- Uses iOS coordinate system (points, not pixels)
- Rectangle format: `"{{x,y},{width,height}}"`
- Swipe coordinates specify starting points

## Limitations

- Requires iOS testing environment to run
- Limited to apps accessible through XCUITest
- Network access required for remote operation
- Some system-level interactions may be restricted

## Security Considerations

- The portal provides full device automation access
- Should only be used in controlled testing environments
- Network access should be restricted to trusted clients
- Consider implementing authentication for production use

## Contributing

This project is part of the larger Droidrun automation framework. Contributions should focus on:
- Enhanced UI state extraction
- Additional gesture support
- Improved error handling
- Performance optimizations

## License

This project is licensed under the MIT License - see the LICENSE file for details.

---

**Note**: This is the iOS portal component of the Droidrun framework. For complete automation workflows, integrate with the corresponding agent component that orchestrates automation tasks using this portal's API.

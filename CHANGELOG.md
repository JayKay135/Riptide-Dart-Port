## 0.3.0

- Updated code to Riptide v2.2.1 and the fixes released since (up to commit `bc3f3f2`)
- Verified compatibility with the C# Riptide library for both the UDP and the TCP transport
- Fixed many bugs of the port, most notably:
  - Message IDs weren't serialized as varints, which shifted the payload of every message
  - Notify messages were sent as unreliable messages, and their headers were corrupted
  - Signed values, floats and doubles were read or written incorrectly
  - Timeouts, RTT measurements, resends and quality disconnects never happened for UDP connections
  - Delayed events (like resends) were executed in the wrong order
  - Transport event handlers weren't called or never unsubscribed, which broke reconnecting and restarting
  - Sequence and ping IDs didn't wrap around
  - UDP datagrams were dropped when sending many messages at once
  - UDP clients bound to the server's port + 1, and multiple clients from the same address collided
  - TCP errors went unhandled and disconnections weren't detected
  - Multi threaded servers and clients failed to start or report errors
  - The message pool, bitfield and message relay filter didn't work like the original
- Exceptions thrown by event subscribers are now caught and logged
- Added tests, including loopback and unreliable network tests
- **Breaking changes**:
  - `Server.start` (and `IServer.start`) now return a `Future` which completes once the server is running
  - `MessageRelayFilter.fromType` and `MessageRelayFilter.fromTypeAndIds` take the values of the enum (e.g. `MessageId.values`) instead of its type
  - `Message.maxPayloadSize` is now static
  - The notify and reliable delivery events of `Connection` are no longer nullable
  - Connecting with custom data no longer releases the given message
  - Increased the minimum Dart SDK version to 3.3.0

#### :arrow_up_small: Riptide version `v2.2.1` (commit `bc3f3f2`)

#### :arrow_down_small: Riptide version `v2.2.0`

## 0.2.0

- Updated code to Riptide v2.2.0

## 0.1.7

- Updated package dependencies

## 0.1.6

- Switched from flutter to dart package

## 0.1.5

- Implemented smaller riptide fixes

#### :arrow_up_small: Riptide version `v2.2.0`

#### :arrow_down_small: Riptide version `v2.1.2`

## 0.1.4

- Improvements for higher pub score

## 0.1.3

- Improvements for higher pub score

## 0.1.2

- Improvements for higher pub score

## 0.1.1

- Improvements for higher pub score

## 0.1.0

- Update to Riptide version `v2.1.2` + added tcp support

#### :arrow_up_small: Riptide version `v2.1.2`

#### :arrow_down_small: Riptide version `v2.0.0`

## 0.0.3

- Removed Tuple package and switched to darts new record types

## 0.0.2

- Improvements for higher pub score

## 0.0.1

- Initial release.

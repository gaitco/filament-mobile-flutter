/// A minimal invalidation event received from a private resource channel.
///
/// Record data is intentionally absent. Screens refetch through their normal
/// authorized HTTP source before displaying any change.
class RealtimeEvent {
  const RealtimeEvent.changed({
    required this.resourceKey,
    this.recordId,
    this.event,
  }) : reconnected = false;

  const RealtimeEvent.reconnected()
    : resourceKey = null,
      recordId = null,
      event = null,
      reconnected = true;

  final String? resourceKey;
  final Object? recordId;
  final String? event;
  final bool reconnected;
}

/// Optional host adapter over a Reverb/Pusher-protocol client.
///
/// The package deliberately takes no WebSocket dependency. Each returned
/// stream represents one private channel; cancelling its subscription must
/// release that channel subscription. The host owns the underlying socket.
abstract interface class FilamentEventTransport {
  Stream<RealtimeEvent> events(String channel);
}

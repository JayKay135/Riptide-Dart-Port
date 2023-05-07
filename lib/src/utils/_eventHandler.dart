abstract class EventArgs {}

/// Defines the function (callback) signature of an Event handler.
typedef EventHandler<EventArgs> = void Function(EventArgs? args);

class Event<EventArgs> {
  List<EventHandler<EventArgs>> eventHandlers = [];

  /// Subscribes an EventHandler to the given Event which will be called when the invoke function is executed
  void subscribe(EventHandler<EventArgs> event) {
    eventHandlers.add(event);
  }

  /// Removes an EventHandlers subscription
  void unsubscribe(EventHandler<EventArgs> event) {
    eventHandlers.remove(event);
  }

  /// Triggers the Event and informs every subscriber about it
  void invoke(EventArgs? t) {
    for (EventHandler<EventArgs> event in eventHandlers) {
      event(t);
    }
  }
}

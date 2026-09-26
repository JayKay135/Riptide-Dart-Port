abstract class EventArgs {}

/// Defines the function (callback) signature of an Event handler.
typedef EventHandler<T> = void Function(T? args);

class Event<T> {
  List<EventHandler<T>> eventHandlers = [];

  /// Subscribes an EventHandler to the given Event which will be called when the invoke function is executed
  ///
  /// NOTE: Just like with C# events, a handler can only be unsubscribed again if the same function instance is passed to
  /// [unsubscribe]. Method tear-offs (e.g. `object.method`) are equal, whereas two identical-looking closures are not.
  void subscribe(EventHandler<T> event) {
    eventHandlers.add(event);
  }

  /// Removes an EventHandlers subscription
  ///
  /// Like C#'s `-=` operator, this removes the most recent subscription of the given handler.
  void unsubscribe(EventHandler<T> event) {
    int index = eventHandlers.lastIndexOf(event);
    if (index != -1) {
      eventHandlers.removeAt(index);
    }
  }

  /// Triggers the Event and informs every subscriber about it
  ///
  /// Like a C# delegate invocation, this informs the handlers which were subscribed when the event was triggered, so
  /// handlers may safely (un)subscribe while the event is being invoked.
  void invoke(T? t) {
    for (EventHandler<T> event in List<EventHandler<T>>.of(eventHandlers)) {
      event(t);
    }
  }
}

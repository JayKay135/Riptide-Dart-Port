import 'dart:math';

/// Represents a rolling series of numbers.
class RollingStat {
  /// The position in the array of the latest item.
  late int _index;

  /// How many of the array's slots are in use.
  late int _slotsFilled;

  late double _mean;

  /// The mean of the stat's values.
  double get mean => _mean;

  /// The sum of the mean subtracted from each value in the array.
  late double _sumOfSquares;

  /// The array used to store the values.
  late List<double> _array;
  List<double> get array => _array;

  /// The variance of the stat's values.
  double get variance => _slotsFilled > 1 ? _sumOfSquares / (_slotsFilled - 1) : 0;

  /// The standard deviation of the stat's values.
  double get standardDev {
    if (variance >= double.minPositive) {
      double root = sqrt(variance);
      return root.isNaN ? 0 : root;
    }
    return 0;
  }

  /// Initializes the stat.
  ///
  /// [sampleSize] : The number of values to store.
  RollingStat(int sampleSize) {
    _index = 0;
    _slotsFilled = 0;
    _mean = 0;
    _sumOfSquares = 0;
    _array = List.generate(sampleSize, (index) => 0);
  }

  /// Adds a new value to the stat.
  ///
  /// [value] : The value to add.
  void add(double value) {
    if (value.isNaN || value.isInfinite) {
      return;
    }

    _index %= _array.length;
    double oldMean = _mean;
    double oldValue = _array[_index];
    _array[_index] = value;
    _index++;

    if (_slotsFilled == _array.length) {
      double delta = value - oldValue;
      _mean += delta / _slotsFilled;
      _sumOfSquares += delta * (value - _mean + (oldValue - oldMean));
    } else {
      _slotsFilled++;
      double delta = value - oldMean;
      _mean += delta / _slotsFilled;
      _sumOfSquares += delta * (value - _mean);
    }
  }

  @override
  String toString() {
    if (_slotsFilled == _array.length) {
      return _array.join(",");
    }

    return _array.take(_slotsFilled).join(",");
  }
}

import 'package:flutter/foundation.dart';

class UnitConversionService {
  // Base units for different measurement types
  static const Map<String, String> _baseUnits = {
    'weight': 'GM',  // Base unit for weight is grams
    'volume': 'ML',  // Base unit for volume is milliliters
    'count': 'PCS',  // Base unit for count is pieces
    'length': 'CM',  // Base unit for length is centimeters
  };

  // Unit conversion factors to base unit
  static const Map<String, Map<String, double>> _conversionFactors = {
    'weight': {
      'GM': 1.0,        // 1 gram = 1 gram
      'KG': 1000.0,     // 1 kg = 1000 grams
      'LB': 453.592,    // 1 pound = 453.592 grams
      'OZ': 28.3495,    // 1 ounce = 28.3495 grams
      'TON': 1000000.0, // 1 ton = 1,000,000 grams
    },
    'volume': {
      'ML': 1.0,        // 1 ml = 1 ml
      'L': 1000.0,      // 1 liter = 1000 ml
      'GAL': 3785.41,   // 1 gallon = 3785.41 ml
      'FL_OZ': 29.5735, // 1 fluid ounce = 29.5735 ml
    },
    'count': {
      'PCS': 1.0,       // 1 piece = 1 piece
      'DOZ': 12.0,      // 1 dozen = 12 pieces
      'GROSS': 144.0,   // 1 gross = 144 pieces
    },
    'length': {
      'CM': 1.0,        // 1 cm = 1 cm
      'M': 100.0,       // 1 meter = 100 cm
      'MM': 0.1,        // 1 mm = 0.1 cm
      'IN': 2.54,       // 1 inch = 2.54 cm
      'FT': 30.48,      // 1 foot = 30.48 cm
    },
  };

  // Get measurement type for a unit
  static String? _getMeasurementType(String unit) {
    for (final entry in _conversionFactors.entries) {
      if (entry.value.containsKey(unit.toUpperCase())) {
        return entry.key;
      }
    }
    return null;
  }

  /// Convert quantity from one unit to another
  /// Returns null if conversion is not possible
  static double? convertQuantity({
    required double quantity,
    required String fromUnit,
    required String toUnit,
  }) {
    try {
      final fromUnitUpper = fromUnit.toUpperCase();
      final toUnitUpper = toUnit.toUpperCase();

      // If same unit, no conversion needed
      if (fromUnitUpper == toUnitUpper) {
        return quantity;
      }

      // Get measurement types
      final fromType = _getMeasurementType(fromUnitUpper);
      final toType = _getMeasurementType(toUnitUpper);

      // Can only convert within same measurement type
      if (fromType == null || toType == null || fromType != toType) {
        debugPrint('❌ Cannot convert $fromUnit to $toUnit - different measurement types');
        return null;
      }

      // Get conversion factors
      final fromFactor = _conversionFactors[fromType]![fromUnitUpper];
      final toFactor = _conversionFactors[toType]![toUnitUpper];

      if (fromFactor == null || toFactor == null) {
        debugPrint('❌ Unknown unit conversion: $fromUnit to $toUnit');
        return null;
      }

      // Convert: quantity * fromFactor / toFactor
      final result = quantity * fromFactor / toFactor;
      
      debugPrint('🔄 Converted: $quantity $fromUnit = ${result.toStringAsFixed(3)} $toUnit');
      return result;
    } catch (e) {
      debugPrint('❌ Unit conversion error: $e');
      return null;
    }
  }

  /// Convert raw material mapping quantity to match stock unit
  /// This is used when consuming raw materials during sales/write-offs
  static double? convertMappingQuantity({
    required double mappingQuantity,
    required String mappingUnit,
    required String stockUnit,
  }) {
    return convertQuantity(
      quantity: mappingQuantity,
      fromUnit: mappingUnit,
      toUnit: stockUnit,
    );
  }

  /// Get all supported units for a measurement type
  static List<String> getSupportedUnits(String measurementType) {
    final type = measurementType.toLowerCase();
    return _conversionFactors[type]?.keys.toList() ?? [];
  }

  /// Get all measurement types
  static List<String> getMeasurementTypes() {
    return _conversionFactors.keys.toList();
  }

  /// Check if two units are compatible (same measurement type)
  static bool areUnitsCompatible(String unit1, String unit2) {
    final type1 = _getMeasurementType(unit1.toUpperCase());
    final type2 = _getMeasurementType(unit2.toUpperCase());
    return type1 != null && type2 != null && type1 == type2;
  }

  /// Get the base unit for a given unit
  static String? getBaseUnit(String unit) {
    final type = _getMeasurementType(unit.toUpperCase());
    return type != null ? _baseUnits[type] : null;
  }

  /// Format quantity with appropriate precision based on unit
  static String formatQuantity(double quantity, String unit) {
    final unitUpper = unit.toUpperCase();
    
    // Use more precision for smaller units
    if (['GM', 'ML', 'CM', 'MM'].contains(unitUpper)) {
      return quantity.toStringAsFixed(2);
    } else if (['KG', 'L', 'M'].contains(unitUpper)) {
      return quantity.toStringAsFixed(3);
    } else {
      return quantity.toStringAsFixed(0); // Whole numbers for pieces
    }
  }

  /// Get display name for unit
  static String getUnitDisplayName(String unit) {
    final unitUpper = unit.toUpperCase();
    const displayNames = {
      'GM': 'Grams',
      'KG': 'Kilograms',
      'LB': 'Pounds',
      'OZ': 'Ounces',
      'TON': 'Tons',
      'ML': 'Milliliters',
      'L': 'Liters',
      'GAL': 'Gallons',
      'FL_OZ': 'Fluid Ounces',
      'PCS': 'Pieces',
      'DOZ': 'Dozen',
      'GROSS': 'Gross',
      'CM': 'Centimeters',
      'M': 'Meters',
      'MM': 'Millimeters',
      'IN': 'Inches',
      'FT': 'Feet',
    };
    return displayNames[unitUpper] ?? unit;
  }
}
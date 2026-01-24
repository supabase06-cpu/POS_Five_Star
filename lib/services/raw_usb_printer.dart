import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class RawUSBPrinter {
  /// Try to send data directly to USB printer port
  /// Returns true if successful, throws exception if printer not connected
  static Future<bool> printRawData(String printerName, Uint8List data) async {
    // Convert printer name to wide string
    final printerNamePtr = printerName.toNativeUtf16();
    
    try {
      // Try to open printer handle directly
      final hPrinter = calloc<IntPtr>();
      
      // Open printer with direct access
      final result = OpenPrinter(
        printerNamePtr,
        hPrinter,
        nullptr,
      );
      
      if (result == 0) {
        // Failed to open printer - likely disconnected
        final error = GetLastError();
        print('❌ Failed to open printer: Error code $error');
        throw Exception('Printer not connected. Please check USB connection and power.');
      }
      
      print('✅ Printer handle opened successfully');
      
      try {
        // Start a raw print job
        final docInfo = calloc<DOC_INFO_1>();
        docInfo.ref.pDocName = 'Raw Print Job'.toNativeUtf16();
        docInfo.ref.pOutputFile = nullptr;
        docInfo.ref.pDatatype = 'RAW'.toNativeUtf16();
        
        final jobId = StartDocPrinter(hPrinter.value, 1, docInfo.cast());
        
        if (jobId == 0) {
          final error = GetLastError();
          print('❌ Failed to start print job: Error code $error');
          throw Exception('Failed to start print job. Printer may be offline.');
        }
        
        print('✅ Print job started with ID: $jobId');
        
        try {
          // Start a page
          if (StartPagePrinter(hPrinter.value) == 0) {
            final error = GetLastError();
            print('❌ Failed to start page: Error code $error');
            throw Exception('Failed to start print page.');
          }
          
          // Write raw data
          final bytesWritten = calloc<Uint32>();
          final dataPtr = calloc<Uint8>(data.length);
          
          // Copy data to native memory
          for (int i = 0; i < data.length; i++) {
            dataPtr[i] = data[i];
          }
          
          final writeResult = WritePrinter(
            hPrinter.value,
            dataPtr.cast(),
            data.length,
            bytesWritten,
          );
          
          if (writeResult == 0) {
            final error = GetLastError();
            print('❌ Failed to write data: Error code $error');
            throw Exception('Failed to send data to printer.');
          }
          
          print('✅ Written ${bytesWritten.value} bytes to printer');
          
          // End page
          if (EndPagePrinter(hPrinter.value) == 0) {
            print('⚠️ Warning: Failed to end page properly');
          }
          
          // End document
          if (EndDocPrinter(hPrinter.value) == 0) {
            print('⚠️ Warning: Failed to end document properly');
          }
          
          // Clean up data pointer
          calloc.free(dataPtr);
          calloc.free(bytesWritten);
          
          print('✅ Raw USB print completed successfully');
          return true;
          
        } finally {
          // Clean up doc info
          calloc.free(docInfo.ref.pDocName);
          calloc.free(docInfo.ref.pDatatype);
          calloc.free(docInfo);
        }
        
      } finally {
        // Always close printer handle
        ClosePrinter(hPrinter.value);
        calloc.free(hPrinter);
      }
      
    } finally {
      // Clean up printer name
      calloc.free(printerNamePtr);
    }
  }
  
  /// Test if printer is accessible
  static Future<bool> testPrinterConnection(String printerName) async {
    try {
      // Just try to open and close the printer - if it works, printer is connected
      final printerNamePtr = printerName.toNativeUtf16();
      final hPrinter = calloc<IntPtr>();
      
      final result = OpenPrinter(printerNamePtr, hPrinter, nullptr);
      
      if (result != 0) {
        ClosePrinter(hPrinter.value);
        calloc.free(hPrinter);
        calloc.free(printerNamePtr);
        return true;
      } else {
        calloc.free(hPrinter);
        calloc.free(printerNamePtr);
        return false;
      }
    } catch (e) {
      return false;
    }
  }
}
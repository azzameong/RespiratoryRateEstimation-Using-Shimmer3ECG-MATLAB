# RespiratoryRateEstimation-Using-Shimmer3ECG-MATLAB
Bachelor's thesis

## Description
This research develops a respiratory rate monitoring system based on electrocardiogram (ECG) signals using the Shimmer ECG device, operated in MATLAB in real time. The system is designed by providing real-time respiratory rate estimation using ECG signals. The estimation is performed using the Pan-Tompkins algorithm to detect QRS complexes, followed by Root Mean Square (RMS) calculation and peak frequency analysis of the power spectrum through Fast Fourier Transform (FFT) to determine the respiratory frequency. The system's results are displayed on a Graphical User Interface (GUI) in the form of ECG signal plots, heart rate, respiratory rate estimation, and classification of respiratory rate levels.

## Device Preparation
1. Prepare the Shimmer3 ECG device and ensure the Bluetooth is connected to the laptop.
2. Attach the electrodes and make sure they are properly placed at the following locations:
- One electrode below the right collarbone (RA)
- One electrode below the left collarbone (LA)
- One electrode around the lower left rib area (LL)

## Aplication Usage
1. Open the RespiratoryRateEstimation.mlapp application to run the respiratory rate monitoring program.
2. Add the ShimmerHandleClass library, which can be downloaded from the following link: https://github.com/ShimmerEngineering/Shimmer-MATLAB-ID/blob/master/ShimmerHandleClass.m
3. Check the Shimmer serial port (Standard Serial over Bluetooth link) being used, for example: COM5. Adjust this in line 40 of the RespiratoryRateEstimation.mlapp code.
4. Run the program.

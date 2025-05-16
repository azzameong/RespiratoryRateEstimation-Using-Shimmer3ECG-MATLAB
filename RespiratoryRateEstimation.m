classdef RespiratoryRateEstimation < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                        matlab.ui.Figure
        TitleLabel                      matlab.ui.control.Label
        SubTitleLabel                   matlab.ui.control.Label
        StartButton                     matlab.ui.control.Button
        StopButton                      matlab.ui.control.Button
        ElapsedTime                     matlab.ui.control.EditField
        Image                           matlab.ui.control.Image
        ElapsedTimeEditFieldLabel       matlab.ui.control.Label
        ECGSignalPanel                  matlab.ui.container.Panel
        UIAxes                          matlab.ui.control.UIAxes
        RespiratoryClassificationPanel  matlab.ui.container.Panel
        Classification                  matlab.ui.control.TextArea
        InformationPanel                matlab.ui.container.Panel
        HeartRate                       matlab.ui.control.NumericEditField
        HeartRateEditFieldLabel         matlab.ui.control.Label
        RespiratoryRate                 matlab.ui.control.NumericEditField
        RespiratoryRateEditFieldLabel   matlab.ui.control.Label
        ComputingTimePanel              matlab.ui.container.Panel
        ComputingTime                   matlab.ui.control.NumericEditField
        UIAxesRR                        matlab.ui.control.UIAxes
    end

    properties (Access = private)
        shimmer          % ShimmerHandleClass object
        Fs = 512         
        T                % Sampling period (calculated as 1/Fs)
        RRsignal
        HRsignal
        stopFlag         % Flag to indicate stop request
        respRateArray = [];
    end

    methods (Access = private)
        function initializeShimmer(app)
            clc;
            comPort = '5';
            app.shimmer = ShimmerHandleClass(comPort);
            connected = app.shimmer.connect();
            if connected
                disp('Shimmer connected');
                app.shimmer.setsamplingrate(app.Fs);
                app.T = 1 / app.Fs;
                app.shimmer.start();
                disp('Shimmer started');
            else
                disp('Failed to connect to Shimmer device');
            end
        end

        function main(app)
            timeStart = tic;
            while ~app.stopFlag
                [data, ~] = app.shimmer.getdata('c');
                pause(app.T);

                [numRow, numCol] = size(data);
                if (numRow > 0 && numCol > 0)
                    signalData = data(:,4);
                    tp = data(:,1);         

                    app.RRsignal = [app.RRsignal; signalData];
                    app.HRsignal = [app.HRsignal; signalData];

                    t = (1:length(app.RRsignal)) / app.Fs;
                    plot(app.UIAxes, t, app.RRsignal);
                    title(app.UIAxes, 'Real-Time ECG Signal');
                    xlabel(app.UIAxes, 'Time (s)');
                    ylabel(app.UIAxes, 'Amplitude');
                    drawnow;

                    if length(app.HRsignal) >= app.Fs * 5
                        app.heartRate(app.HRsignal, tp);
                        app.HRsignal = [];
                    end

                    if length(app.RRsignal) >= app.Fs * 60
                        computationStart = tic;

                        app.respRate(app.RRsignal, tp);

                        plot(app.UIAxesRR, app.respRateArray, '-o');
                        title(app.UIAxesRR, 'Estimated Respiratory Rate');
                        xlabel(app.UIAxesRR, 'Time (minutes)');
                        ylabel(app.UIAxesRR, 'Breaths/minute');
                        grid(app.UIAxesRR, 'on');
                        drawnow;

                        app.RRsignal = [];

                        computationTime = toc(computationStart);
                        cTime = double(computationTime);
                        app.ComputingTime.Value = cTime;
                    end

                    elapsedTime = toc(timeStart);
                    etime = num2str(elapsedTime);
                    app.ElapsedTime.Value = etime;
                end
            end

            app.shimmer.stop();
            app.shimmer.disconnect();
            disp('Shimmer disconnected');
        end

        function respRate(app, ecg_data, tp)
            allScaledRMS = [];
            allRintervals = [];

            lowCutoff = 8;
            highCutoff = 40;
            [b, a] = butter(2, [lowCutoff highCutoff] / (app.Fs / 2), 'bandpass');
            filtered_ecg = filtfilt(b, a, ecg_data);
            diff_ecg = diff(filtered_ecg);
            squared_ecg = diff_ecg .^ 2;
            window_size = round(0.120 * app.Fs);
            mwi_ecg = conv(squared_ecg, ones(1, window_size) / window_size, 'same');
            threshold = max(mwi_ecg) * 0.4;
            [~, qrs_locs] = findpeaks(mwi_ecg, 'MinPeakHeight', threshold, 'MinPeakDistance', round(0.2 * app.Fs));

            qrs_window = round(0.08 * app.Fs); 
            num_qrs = length(qrs_locs);
            rms_values = zeros(num_qrs, 1); 

            for i = 1:num_qrs
                r_loc = qrs_locs(i);
                start_idx = max(r_loc - qrs_window, 1);
                end_idx = min(r_loc + qrs_window, length(filtered_ecg));
                extracted_qrs = filtered_ecg(start_idx:end_idx);

                if length(extracted_qrs) < (qrs_window * 2 + 1)
                    extracted_qrs = padarray(extracted_qrs, [(qrs_window * 2 + 1) - length(extracted_qrs), 0], 0, 'post');
                end

                rms_values(i) = sqrt(mean(extracted_qrs .^ 2));
            end

            scaled_rms_values = rms_values * 1000;
            allScaledRMS = [allScaledRMS; scaled_rms_values];

            if length(qrs_locs) > 1
                rr_intervals = diff(qrs_locs) / app.Fs;
                allRintervals = [allRintervals; rr_intervals];
            end

            disp('Current Scaled RMS Values:');
            disp(allScaledRMS);
            disp('Current R-R Intervals (s):');
            disp(allRintervals);

            t2 = (1:length(mwi_ecg)) / app.Fs;
            plot(t2, mwi_ecg);
            hold('on');
            plot(qrs_locs / app.Fs, mwi_ecg(qrs_locs), 'ro');
            hold('off');
            title('ECG Signal after Pan-Tompkins Processing');
            xlabel('Time (s)');
            ylabel('Amplitude');
            drawnow;

            rms_window_size = 16;
            rr_window_size = 15;

            num_iterations = length(allScaledRMS) - rms_window_size + 1;
            median_rr = zeros(num_iterations, 1);
            fpeak_results = zeros(num_iterations, 1);
            resp_rate = zeros(num_iterations, 1);

            if length(allScaledRMS) < rms_window_size
                disp('RMS window size is insufficient. Setting RespRate to 0.');
                app.respRateArray = [app.respRateArray, 0];
                app.RespiratoryRate.Value = 0;
                app.Classification.Value = 'Insufficient Data';
                app.Classification.BackgroundColor = [0.5, 0.5, 0.5];
                return;
            end

            for i = 1:num_iterations
                rr_window = allRintervals(i:i + rr_window_size - 1);
                median_rr(i) = median(rr_window);

                rms_window = allScaledRMS(i:i + rms_window_size - 1);
                fft_result = fft(rms_window);
                n = length(rms_window);
                frequencies = (0:n/2-1) / n; 
                power_spectrum = abs(fft_result(1:n/2)).^2; 

                min_freq = 0.083;
                max_freq = 0.667;
                valid_indices = (frequencies >= min_freq & frequencies <= max_freq);
                filtered_frequencies = frequencies(valid_indices);
                filtered_power_spectrum = power_spectrum(valid_indices);

                [~, fpeak_idx] = max(filtered_power_spectrum);
                fpeak_results(i) = filtered_frequencies(fpeak_idx);

                resp_rate(i) = fpeak_results(i) * 60 / median_rr(i);
            end

            results_table = table(median_rr, fpeak_results, resp_rate, 'VariableNames', {'MedianRR', 'Fpeak', 'RespRate'});

            disp(results_table);

            overall_median_resp_rate = median(resp_rate);
            app.respRateArray = [app.respRateArray, overall_median_resp_rate];
            app.RespiratoryRate.Value = double(overall_median_resp_rate);

            disp(['Median dari seluruh RespRate: ', num2str(overall_median_resp_rate)]);

            if overall_median_resp_rate < 12
                classification = 'Slow';
                app.Classification.BackgroundColor = [0, 0, 1];
            elseif overall_median_resp_rate <= 20
                classification = 'Normal';
                app.Classification.BackgroundColor = [0, 1, 0];
            else
                classification = 'Fast';
                app.Classification.BackgroundColor = [1, 0, 0];
            end
            app.Classification.Value = classification;
        end

        function heartRate(app, ecgHr, tp)
            lowCutoff = 0.5;
            highCutoff = 50;
            [b, a] = butter(2, [lowCutoff highCutoff] / (app.Fs / 2), 'bandpass');
            filtered_ecg = filtfilt(b, a, ecgHr);
            diff_ecg = diff(filtered_ecg);
            squared_ecg = diff_ecg .^ 2;
            window_size = round(0.120 * app.Fs);
            mwi_ecg = conv(squared_ecg, ones(1, window_size) / window_size, 'same');
            threshold = max(mwi_ecg) * 0.4;

            [~, qrs_locs] = findpeaks(mwi_ecg, 'MinPeakHeight', threshold, 'MinPeakDistance', round(0.2 * app.Fs));

            rr_intervals = diff(qrs_locs) / app.Fs;

            if ~isempty(rr_intervals)
                heart_rate = 60 / mean(rr_intervals);
            else
                heart_rate = 0;
            end

            app.HeartRate.Value = double(heart_rate);
        end

    end

    % Callbacks that handle component events
    methods (Access = private)

        % Button pushed function: StartButton
        function StartButtonPushed(app, event)
            app.stopFlag = false;
            app.initializeShimmer();
            app.main();
        end

        % Button pushed function: StopButton
        function StopButtonPushed(app, event)
            app.stopFlag = true;
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Get the file path for locating images
            pathToMLAPP = fileparts(mfilename('fullpath'));

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 643 776];
            app.UIFigure.Name = 'MATLAB App';

            % Create UIAxesRR
            app.UIAxesRR = uiaxes(app.UIFigure);
            title(app.UIAxesRR, 'Estimated RR')
            xlabel(app.UIAxesRR, 'Time (minute)')
            ylabel(app.UIAxesRR, 'Breaths/min')
            zlabel(app.UIAxesRR, 'Z')
            app.UIAxesRR.Position = [36 24 418 185];

            % Create ComputingTimePanel
            app.ComputingTimePanel = uipanel(app.UIFigure);
            app.ComputingTimePanel.TitlePosition = 'centertop';
            app.ComputingTimePanel.Title = 'Computing Time';
            app.ComputingTimePanel.FontWeight = 'bold';
            app.ComputingTimePanel.Position = [466 126 152 65];

            % Create ComputingTime
            app.ComputingTime = uieditfield(app.ComputingTimePanel, 'numeric');
            app.ComputingTime.Editable = 'off';
            app.ComputingTime.Position = [26 12 100 22];

            % Create InformationPanel
            app.InformationPanel = uipanel(app.UIFigure);
            app.InformationPanel.TitlePosition = 'centertop';
            app.InformationPanel.Title = 'Information';
            app.InformationPanel.FontWeight = 'bold';
            app.InformationPanel.Position = [297 234 321 108];

            % Create RespiratoryRateEditFieldLabel
            app.RespiratoryRateEditFieldLabel = uilabel(app.InformationPanel);
            app.RespiratoryRateEditFieldLabel.HorizontalAlignment = 'right';
            app.RespiratoryRateEditFieldLabel.Position = [46 56 95 22];
            app.RespiratoryRateEditFieldLabel.Text = 'Respiratory Rate';

            % Create RespiratoryRate
            app.RespiratoryRate = uieditfield(app.InformationPanel, 'numeric');
            app.RespiratoryRate.AllowEmpty = 'on';
            app.RespiratoryRate.Editable = 'off';
            app.RespiratoryRate.Position = [156 56 100 22];

            % Create HeartRateEditFieldLabel
            app.HeartRateEditFieldLabel = uilabel(app.InformationPanel);
            app.HeartRateEditFieldLabel.HorizontalAlignment = 'right';
            app.HeartRateEditFieldLabel.Position = [78 14 63 22];
            app.HeartRateEditFieldLabel.Text = 'Heart Rate';

            % Create HeartRate
            app.HeartRate = uieditfield(app.InformationPanel, 'numeric');
            app.HeartRate.Editable = 'off';
            app.HeartRate.Position = [156 14 100 22];

            % Create RespiratoryClassificationPanel
            app.RespiratoryClassificationPanel = uipanel(app.UIFigure);
            app.RespiratoryClassificationPanel.TitlePosition = 'centertop';
            app.RespiratoryClassificationPanel.Title = 'Respiratory Classification';
            app.RespiratoryClassificationPanel.FontWeight = 'bold';
            app.RespiratoryClassificationPanel.Position = [36 234 250 108];

            % Create Classification
            app.Classification = uitextarea(app.RespiratoryClassificationPanel);
            app.Classification.Editable = 'off';
            app.Classification.HorizontalAlignment = 'center';
            app.Classification.FontSize = 20;
            app.Classification.FontWeight = 'bold';
            app.Classification.Placeholder = 'Loading...';
            app.Classification.Position = [18 14 215 64];

            % Create ECGSignalPanel
            app.ECGSignalPanel = uipanel(app.UIFigure);
            app.ECGSignalPanel.TitlePosition = 'centertop';
            app.ECGSignalPanel.Title = 'ECG Signal';
            app.ECGSignalPanel.FontWeight = 'bold';
            app.ECGSignalPanel.Position = [36 360 582 238];

            % Create UIAxes
            app.UIAxes = uiaxes(app.ECGSignalPanel);
            xlabel(app.UIAxes, 'Time (s)')
            ylabel(app.UIAxes, 'mV')
            zlabel(app.UIAxes, 'Z')
            app.UIAxes.Position = [9 17 563 185];

            % Create ElapsedTimeEditFieldLabel
            app.ElapsedTimeEditFieldLabel = uilabel(app.UIFigure);
            app.ElapsedTimeEditFieldLabel.HorizontalAlignment = 'right';
            app.ElapsedTimeEditFieldLabel.FontWeight = 'bold';
            app.ElapsedTimeEditFieldLabel.Position = [54 622 82 22];
            app.ElapsedTimeEditFieldLabel.Text = 'Elapsed Time';

            % Create Image
            app.Image = uiimage(app.UIFigure);
            app.Image.Position = [492 43 100 50];
            app.Image.ImageSource = fullfile(pathToMLAPP, 'filkom.png');

            % Create ElapsedTime
            app.ElapsedTime = uieditfield(app.UIFigure, 'text');
            app.ElapsedTime.Editable = 'off';
            app.ElapsedTime.Position = [151 622 100 22];

            % Create StopButton
            app.StopButton = uibutton(app.UIFigure, 'push');
            app.StopButton.ButtonPushedFcn = createCallbackFcn(app, @StopButtonPushed, true);
            app.StopButton.Position = [535 622 66 22];
            app.StopButton.Text = 'Stop';

            % Create StartButton
            app.StartButton = uibutton(app.UIFigure, 'push');
            app.StartButton.ButtonPushedFcn = createCallbackFcn(app, @StartButtonPushed, true);
            app.StartButton.Position = [453 622 66 22];
            app.StartButton.Text = 'Start';

            % Create SubTitleLabel
            app.SubTitleLabel = uilabel(app.UIFigure);
            app.SubTitleLabel.Position = [111 678 431 22];
            app.SubTitleLabel.Text = 'Real-Time Estimation of Respiratory Rate Based on Electrocardiogram Signals';

            % Create TitleLabel
            app.TitleLabel = uilabel(app.UIFigure);
            app.TitleLabel.HorizontalAlignment = 'center';
            app.TitleLabel.FontSize = 18;
            app.TitleLabel.FontWeight = 'bold';
            app.TitleLabel.Position = [184 711 280 23];
            app.TitleLabel.Text = 'YOGA RESPIRATION TRACKER';

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = RespiratoryRateEstimation

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end
function [outbins, nch, fs] = mu_ks_getBins_TDT(BLOCKPATHs, varargin)
%% Validate inputs
mIp = inputParser;
mIp.addParameter("Channel", [], @(x) validateattributes(x, 'numeric', {'vector', 'integer', 'positive'}));
mIp.addParameter("Format", 'i16');
mIp.addParameter("ScaleFactor", 1e6, @(x) validateattributes(x, 'numeric', {'scalar', 'positive'}));
mIp.addParameter("dt", 10, @(x) validateattributes(x, 'numeric', {'scalar', 'positive'}));
mIp.addParameter("SkipExisted", true, @(x) validateattributes(x, 'logical', {'scalar'}));
% 2026-11-01: the TDT store name is no longer hard-coded. Blocks may carry
% Llfp / Wave / Raw_ / etc.; a missing store now produces a clear error that
% lists what the block actually contains.
mIp.addParameter("Store", 'Wave', @(x) ischar(x) || isstring(x));
mIp.parse(varargin{:});

CHANNEL = unique(mIp.Results.Channel);
FORMAT = validatestring(mIp.Results.Format, {'i16', 'f32'});
SCALE_FACTOR = mIp.Results.ScaleFactor;
TIME_DELTA = mIp.Results.dt; % sec
skipExisted = mIp.Results.SkipExisted;
STORE = char(mIp.Results.Store);

BLOCKPATHs = cellstr(BLOCKPATHs);

%% Export to binary file
outbins = cell(numel(BLOCKPATHs), 1);
for blk = 1:numel(BLOCKPATHs)
    BLOCKPATH = BLOCKPATHs{blk};

    if ~exist(BLOCKPATH, "dir")
        error('TDT Block folder %s does not exist', BLOCKPATH);
    end

    % 2026-11-01: write to <tank>\BIN\<Block-N>_<store>.bin instead of inside the
    % raw block folder (raw data is read-only). Legacy in-block files are still
    % picked up so previously exported blocks are not re-exported.
    [SAVEPATH, LEGACYPATH] = mu.binPath(BLOCKPATH, STORE);
    if ~isfile(SAVEPATH) && isfile(LEGACYPATH)
        warning('mu_ks_getBins_TDT:legacyBin', ...
            'Using the legacy in-block binary %s (new location would be %s).', ...
            LEGACYPATH, SAVEPATH);
        SAVEPATH = LEGACYPATH;
    end
    outbins{blk} = SAVEPATH;

    % P0-2: refuse a truncated .sev file instead of letting TDTbin2mat infer
    % a wrong sampling rate from the file size (see mu.sevCheck)
    sevRep = mu.sevCheck(BLOCKPATH);

    if blk == 1
        data = TDTbin2mat(BLOCKPATH, 'TYPE', {'streams'}, 'STORE', STORE, 'T2', 0.1);
        if ~isfield(data.streams, STORE)
            avail = strjoin(fieldnames(data.streams)', ', ');
            error('mu_ks_getBins_TDT:noStore', ...
                'Store "%s" not found in %s. Available stores: %s', STORE, BLOCKPATH, avail);
        end
        fs = data.streams.(STORE).fs;
        nch = size(data.streams.(STORE).data, 1);
        if isempty(CHANNEL)
            CHANNEL = 1:nch;
        else
            assert(max(CHANNEL) <= nch, 'Channel number should not exceed %d', nch);
        end

        % P1-1: duration must come from the data itself, never from
        % data.info.duration (that field is a datestr built from tank
        % start/stop times, e.g. 51.2 s for a 600.12 s recording).
        % The tank fs is authoritative; the .sev header rate can disagree
        % (measured: header 64.2475 Hz vs tank 1017.2526 Hz).
        if ~isempty(sevRep)
            nSamples = max([sevRep.nSamples]);
            fprintf('Recording duration: %.3f s (%.0f samples / %.4f Hz)\n', ...
                nSamples / fs, nSamples, fs);
        end
        if isfield(data, 'info') && isfield(data.info, 'duration')
            fprintf(['NOTE: data.info.duration = %s is a datestr, not seconds; ', ...
                     'do not use it for trial windows.\n'], data.info.duration);
        end
    end

    if exist(SAVEPATH, "file")
        fprintf('File already exists: %s', SAVEPATH);
        if ~skipExisted
            key = validateinput('Continue? y/[n] ', @(x) isempty(x) || ismember(string(x), ["y", "n"]), 's');
            if isempty(key) || strcmpi(key, "n")
                continue;
            end
        else
            disp('Skip exporting existed binary file');
            continue;
        end
    end

    fid = fopen(SAVEPATH, 'wb');
    if fid < 0
        % make sure the new <tank>\BIN folder exists before giving up
        outDir = fileparts(SAVEPATH);
        if ~isfolder(outDir), mkdir(outDir); end
        fid = fopen(SAVEPATH, 'wb');
        if fid < 0
            error('mu_ks_getBins_TDT:openFailed', 'Cannot write %s', SAVEPATH);
        end
    end
    T1 = 0;
    T2 = T1 + TIME_DELTA;

    data = TDTbin2mat(BLOCKPATH, 'STORE', STORE, 'T1', T1, 'T2', T2);
    dataSeg = data.streams.(STORE).data(CHANNEL, :);

    % loop through data in TIME_DELTA increments
    while ~isempty(dataSeg)
        if strcmpi(FORMAT, 'i16')
            fwrite(fid, SCALE_FACTOR * reshape(dataSeg, 1, []), 'integer*2');
        elseif strcmpi(FORMAT, 'f32')
            fwrite(fid, SCALE_FACTOR * reshape(dataSeg, 1, []), 'single');
        end

        T1 = T2;
        T2 = T2 + TIME_DELTA;
        try
            data = TDTbin2mat(BLOCKPATH, 'STORE', STORE, 'T1', T1, 'T2', T2);
            dataSeg = data.streams.(STORE).data(CHANNEL, :);
        catch
            dataSeg = [];
        end
    end

    fprintf('Wrote %s to output file %s\n', STORE, SAVEPATH);
    fprintf('Sampling Rate: %.6f Hz\n', fs);
    fprintf('Num Channels: %d\n', numel(CHANNEL));
    fclose(fid);
end

return;
end

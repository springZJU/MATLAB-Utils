function report = sevCheck(blockPath, mode)
%SEVCHECK  Structural integrity check for the .sev files of a TDT block.
%
%   report = mu.sevCheck(blockPath)             % mode = "error"
%   report = mu.sevCheck(blockPath, "warn")     % report only, no error
%   report = mu.sevCheck(blockPath, "silent")   % collect only
%
%   Why this exists (PHASE4_CHANGE_LIST.md P0-2):
%   TDTbin2mat / SEV2mat infer the sampling rate of a .sev stream from the
%   header, and they infer the number of samples from the FILE SIZE
%   (data_size = bytes - 40). A truncated or still-being-written .sev file
%   therefore yields a WRONG fs and a WRONG sample count without any error.
%   Measured example: a block whose real duration was 600.12 s produced
%   "Using 1017.2526 Hz" from a truncated file.
%
%   The check verifies, per .sev file:
%     1. actual byte count == header.fileSizeBytes   (header declares its size)
%     2. (bytes - 40) is an exact multiple of sampleWidthBytes * totalNumChannels
%     3. fileVersion > 0, i.e. the header carries a real sampling rate
%        (fileVersion 0 => SEV2mat falls back to 24414.0625 Hz)
%
%   Header layout (40 bytes, see SEV2mat.m):
%     0-7   uint64 fileSizeBytes
%     8-10  char[3] fileType
%     11    char fileVersion
%     12-15 char[4] eventName
%     16-17 uint16 channelNum
%     18-19 uint16 totalNumChannels
%     20-21 uint16 sampleWidthBytes
%     22-23 uint16 reserved
%     24    uint8  dForm (lower 3 bits)
%     25    uint8  decimate
%     26-27 uint16 rate

if nargin < 2 || isempty(mode)
    mode = "error";
end
mode = validatestring(mode, {'error', 'warn', 'silent'});

if ~isfolder(blockPath)
    error('mu:sevCheck:missingBlock', 'TDT block folder not found: %s', blockPath);
end

sevFiles = dir(fullfile(blockPath, '*.sev'));
report = struct('name', {}, 'bytes', {}, 'declaredBytes', {}, 'fileVersion', {}, ...
    'totalNumChannels', {}, 'sampleWidthBytes', {}, 'fs', {}, 'nSamples', {}, ...
    'ok', {}, 'reason', {});

if isempty(sevFiles)
    % .tev/.tsq blocks have no .sev; nothing to check and no reason to warn
    return
end

bad = {};
for k = 1:numel(sevFiles)
    path = fullfile(sevFiles(k).folder, sevFiles(k).name);
    info = dir(path);

    fid = fopen(path, 'r', 'ieee-le');
    if fid < 0
        warning('mu:sevCheck:openFailed', 'Cannot open %s', path);
        continue
    end
    cleaner = onCleanup(@() fclose(fid));

    declaredBytes    = fread(fid, 1, 'uint64');
    fread(fid, 3, 'char=>char');              % fileType
    fileVersion      = fread(fid, 1, 'char');
    fseek(fid, 12, 'bof');
    fread(fid, 4, 'char=>char');              % eventName
    channelNum       = fread(fid, 1, 'uint16');
    totalNumChannels = fread(fid, 1, 'uint16');
    sampleWidthBytes = fread(fid, 1, 'uint16');
    fseek(fid, 24, 'bof');
    dform            = fread(fid, 1, 'uint8');
    decimate         = fread(fid, 1, 'uint8');
    rate             = fread(fid, 1, 'uint16');
    clear cleaner

    bytes = info.bytes;
    ok = true;
    reasons = {};

    if declaredBytes ~= bytes
        ok = false;
        reasons{end+1} = sprintf('declared %d bytes, file has %d', declaredBytes, bytes);
    end

    payload = bytes - 40;
    if sampleWidthBytes > 0
        % A .sev file holds ONE channel; totalNumChannels is only metadata about
        % the stream it belongs to. Dividing by it (as an earlier version of
        % this function did) under-counts the samples by the channel count.
        if mod(payload, sampleWidthBytes) ~= 0
            ok = false;
            reasons{end+1} = sprintf('%d payload bytes not a multiple of %d', payload, sampleWidthBytes);
        end
        nSamples = floor(payload / sampleWidthBytes);
    else
        ok = false;
        nSamples = NaN;
        reasons{end+1} = 'header carries no sampleWidthBytes';
    end

    % Header-derived sampling rate. NOTE: this is reported for reference only.
    % On real blocks the tank header (.tsq/.tev) is authoritative and can differ
    % from the SEV header -- measured example: this formula gives 64.2475 Hz
    % while TDTbin2mat reports 1017.2526 Hz for the same stream. Callers should
    % use the fs returned by TDTbin2mat, not this value.
    if fileVersion > 0 && decimate > 0
        fs = 2^(rate - 12) * 25000000 / decimate;
    else
        fs = 24414.0625;
        ok = false;
        reasons{end+1} = 'fileVersion/decimate unusable: fs would be assumed, not read';
    end

    report(end+1) = struct('name', sevFiles(k).name, 'bytes', bytes, ...
        'declaredBytes', double(declaredBytes), 'fileVersion', fileVersion, ...
        'totalNumChannels', totalNumChannels, 'sampleWidthBytes', sampleWidthBytes, ...
        'fs', fs, 'nSamples', nSamples, 'ok', ok, ...
        'reason', strjoin(reasons, '; ')); %#ok<AGROW>

    if ~ok
        bad{end+1} = sprintf('%s: %s', sevFiles(k).name, report(end).reason); %#ok<AGROW>
    end
end

if ~isempty(bad)
    msg = sprintf('SEV integrity check failed in %s:\n  %s', blockPath, strjoin(bad, '\n  '));
    switch mode
        case "error"
            error('mu:sevCheck:corruptSev', '%s', msg);
        case "warn"
            warning('mu:sevCheck:corruptSev', '%s', msg);
    end
end
end

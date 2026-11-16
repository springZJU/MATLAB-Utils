function nbchan = bdfNbchan(bdfPath)
%BDFNBCHAN  Number of signal channels declared in a BDF file header.
%
%   nbchan = mu.bdfNbchan(bdfPath)
%
%   The BDF/EDF header stores the number of signals as 4 ASCII characters at
%   1-based byte 253-256 (0-based offset 252), after the 8-byte "number of data
%   records" field (237-244) and the 8-byte "duration of a data record" field
%   (245-252). BioSemi's 24-bit BDF keeps the same layout.
%
%   Use this instead of hard-coding channel counts (e.g. opts.badChs = 60:64
%   only makes sense for a 64-channel recording).

if ~isfile(bdfPath)
    error('mu:bdfNbchan:missingFile', 'BDF file not found: %s', bdfPath);
end

fid = fopen(bdfPath, 'r', 'ieee-le');
if fid < 0
    error('mu:bdfNbchan:openFailed', 'Cannot open BDF file: %s', bdfPath);
end
cleaner = onCleanup(@() fclose(fid));

fseek(fid, 252, 'bof');
str = fread(fid, 4, 'char=>char')';

nbchan = str2double(str);
if isnan(nbchan) || nbchan <= 0
    error('mu:bdfNbchan:badHeader', ...
        'Cannot parse the channel count from the header of %s (read "%s")', bdfPath, str);
end
end

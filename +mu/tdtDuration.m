function [dur, ok] = tdtDuration(data, streamName)
%TDTDURATION  Real recording duration of a TDT block, in seconds.
%
%   [dur, ok] = mu.tdtDuration(data, streamName)
%
%   Why this exists (PHASE4_CHANGE_LIST.md P1-1):
%   data.info.duration returned by TDTbin2mat is a datestr string built from
%   the tank start/stop times -- NOT the number of seconds of data. Measured
%   example: a block whose real duration was 600.12 s reported 51.2 s.
%   Never use data.info.duration for trial windows or completeness checks.
%
%   Inputs
%     data       : struct returned by TDTbin2mat
%     streamName : optional; defaults to the first stream
%
%   Outputs
%     dur : size(data.streams.(streamName).data, 2) / fs   [s]
%     ok  : false when the last epoc onset falls beyond dur (data truncated)

if nargin < 2 || isempty(streamName)
    f = fieldnames(data.streams);
    if isempty(f)
        error('mu:tdtDuration:noStream', 'The block contains no stream.');
    end
    streamName = f{1};
end

stream = data.streams.(streamName);
fs = stream.fs;
dur = size(stream.data, 2) / fs;

ok = true;
if isfield(data, 'epocs') && ~isempty(data.epocs)
    names = fieldnames(data.epocs);
    for k = 1:numel(names)
        onset = data.epocs.(names{k}).onset;
        if ~isempty(onset) && max(onset) > dur
            ok = false;
            warning('mu:tdtDuration:onsetBeyondData', ...
                'Epoc "%s" has an onset at %.3f s but the stream only lasts %.3f s.', ...
                names{k}, max(onset), dur);
        end
    end
end
end

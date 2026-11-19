function [latency, P, spikes, index] = calLatencyDual(trials, windowOnset, windowBase, windowPost, th, nStart, tTh, minLatency)
%CALLATENCYDUAL  Response latency with automatic upward/downward detection.
%
% [latency, P, spikes, index] = mu.calLatencyDual(trials, windowOnset, ...
%       windowBase, windowPost, th, nStart, tTh, minLatency)
%
% Input
%   trials      : cell array of per-trial spike times (ms), one vector per trial
%   windowOnset : [t1 t2] response window (ms)
%   windowBase  : baseline window (ms) for the upward test
%   windowPost  : post window (ms) used as the reference for the downward test
%   th          : Poisson cumulative-probability threshold (default 1e-6)
%   nStart      : start testing from the nStart-th spike (default 5)
%   tTh         : latest accepted latency (default 50 ms)
%   minLatency  : earliest accepted latency (default 10 ms)
%
% Output
%   latency     : detected latency (ms); [] if none
%   P           : Poisson cumulative probability series used
%   spikes      : spike times used for the decision
%   index       : +1 upward, -1 downward, 0 none
%
% Method (same as the reference project's calLatency_Dual)
%   Upward: for the k-th spike inside [windowOnset], the expected count under
%           the baseline rate is lambda = nTrial * rateBase * t / 1000;
%           P = 1 - poisscdf(k-1, lambda). The first k with P < th, t > minLatency
%           and t < tTh gives the latency.
%   Downward (only when no upward latency was found): the same test is run on
%           time-reversed spikes inside the window, referenced to windowPost;
%           latency is measured back from windowOnset(2).
%
% Note: the reference implementation called calFR (MultiChannelProcess); here
%       mu_calFR is used, which counts spikes with >= w(1) & <= w(2).
%
% See also mu_calLatency, mu.isChangeResp.

narginchk(4, 8);
if nargin < 5 || isempty(th), th = 1e-6; end
if nargin < 6 || isempty(nStart), nStart = 5; end
if nargin < 7 || isempty(tTh), tTh = 50; end
if nargin < 8 || isempty(minLatency), minLatency = 10; end

trials = reshape(trials, [], 1);
trials = cellfun(@(x) reshape(x, [], 1), trials, 'UniformOutput', false);
allSpikes = cell2mat(trials(:));

% ---- Step 1: baseline rates ------------------------------------------------
sprateOn = mean(mu_calFR(trials, windowBase));
spratePost = mean(mu_calFR(trials, windowPost));

% ---- Step 2: upward latency ------------------------------------------------
spikesOn = sort(allSpikes(allSpikes >= windowOnset(1) & allSpikes <= windowOnset(2)));
spikesOn = spikesOn - windowOnset(1);
tThOn = tTh - windowOnset(1);
minLatencyOn = minLatency - windowOnset(1);
latencyOn = [];
Pon = [];
if numel(spikesOn) >= nStart
    spikesUse = spikesOn(nStart:end);
    n = nStart:numel(spikesOn);
    lambda = numel(trials) * sprateOn * spikesUse / 1000;
    Pon = zeros(numel(n), 1);
    for i = 1:numel(n)
        Pon(i) = 1 - poisscdf(n(i) - 1, lambda(i));
    end
    validOn = (Pon < th) & (spikesUse > minLatencyOn) & (spikesUse < tThOn);
    latencyOn = spikesUse(find(validOn, 1));
    latencyOn = latencyOn + windowOnset(1);
end

% ---- Step 3: downward latency (only if upward failed) ----------------------
latencyOff = [];
Poff = [];
spikesRev = [];
if isempty(latencyOn)
    spikesRev = sort(windowOnset(2) - allSpikes(allSpikes >= windowOnset(1) & allSpikes <= windowOnset(2)));
    if numel(spikesRev) >= nStart
        spikesRev = sort(spikesRev);
        spikesRevUse = spikesRev(nStart:end);
        nRev = nStart:numel(spikesRev);
        lambdaRev = numel(trials) * spratePost * spikesRevUse / 1000;
        PoffRaw = zeros(numel(nRev), 1);
        for i = 1:numel(nRev)
            PoffRaw(i) = 1 - poisscdf(nRev(i) - 1, lambdaRev(i));
        end
        validRev = (PoffRaw < th) & (spikesRevUse > minLatency) & (spikesRevUse < tTh);
        revLatency = spikesRevUse(find(validRev, 1));
        if ~isempty(revLatency)
            latencyOff = windowOnset(2) - revLatency;
            Poff = PoffRaw;
        end
    end
end

% ---- Step 4: output --------------------------------------------------------
if ~isempty(latencyOff)
    latency = latencyOff;
    P = Poff;
    spikes = spikesRev;
    index = -1;
elseif ~isempty(latencyOn)
    latency = latencyOn;
    P = Pon;
    spikes = spikesOn;
    index = 1;
else
    latency = [];
    P = [];
    spikes = [];
    index = 0;
end

return;
end

function [h, info] = isChangeResp(trials, varargin)
%ISCHANGERESP  Change-response flag (H_change) — RAT_LocalGlobal criterion.
%
% [h, info] = mu.isChangeResp(trials, 'Name', Value, ...)
%
% Input
%   trials : cell array (nCond x 1); trials{c} is a cell array of per-trial
%            spike times (ms) aligned to the change point (0 = ICI change).
%
% Options
%   'condIdx'     : conditions; H_change = ANY(hc(condIdx)) (default all)
%   'winResp'     : response window, ms (default [10 130])
%   'winBase'     : baseline window, ms (default [-200 0])
%   'nBoot'       : bootstrap resamples (default 1000)
%   'bootRatio'   : significance ratio (default 0.001)
%   'minSpkTrial' : minimum spikes per trial in winResp (default 2)
%   'latTh'       : Poisson threshold for latency (default 1e-3)
%   'latNStart'   : first spike used for latency (default 5)
%   'latTTh'      : latest latency, ms (default 100)
%   'latMin'      : earliest latency, ms (default 10)
%   'seed'        : bootstrap seed (default [] = global RNG)
%
% Output
%   h    : logical scalar
%   info : struct with .h (per condition), .bootRatio, .frResp, .frBase,
%          .latency, .latIndex
%
% Criterion (per condition c), same as the reference buildNeuronSet.m:
%   d     = per-trial FR(winResp) - FR(winBase)
%   b     = bootstrap distribution of mean(d), nBoot resamples
%   hBoot = min(#b<0, #b>0) / nBoot < bootRatio       (one-sided at 99.9%)
%   hLat  = ~isempty(mu.calLatencyDual(...))
%   hFR   = mean(FR_resp) > minSpkTrial * 1000 / diff(winResp)
%   hc    = hBoot && hLat && hFR
%   H_change = any(hc(condIdx))
%
% The reference project applied this to the two "whole" conditions
% (condIdx = [8 16] for Reg4-5 / Reg5-4, i.e. the entire 2 s is the inserted
% ICI) and required AT LEAST ONE to pass.
%
% See also mu.isOnsetResp, mu.bootstrp, mu.calLatencyDual, mu_calFR.

narginchk(1, inf);
nCond = numel(trials);
opt = mu.nv2struct(varargin);
condIdx = mu.getor(opt, 'condIdx', 1:nCond);
winResp = mu.getor(opt, 'winResp', [10 130]);
winBase = mu.getor(opt, 'winBase', [-200 0]);
nBoot = mu.getor(opt, 'nBoot', 1000);
bootRatio = mu.getor(opt, 'bootRatio', 0.001);
minSpkTrial = mu.getor(opt, 'minSpkTrial', 2);
latTh = mu.getor(opt, 'latTh', 1e-3);
latNStart = mu.getor(opt, 'latNStart', 5);
latTTh = mu.getor(opt, 'latTTh', 100);
latMin = mu.getor(opt, 'latMin', 10);
seed = mu.getor(opt, 'seed', []);

hC = false(nCond, 1);
br = nan(nCond, 1);
frR = nan(nCond, 1);
frB = nan(nCond, 1);
lat = nan(nCond, 1);
latIdx = zeros(nCond, 1);
for c = 1:nCond
    sp = trials{c};
    if isempty(sp), continue; end
    r = mu_calFR(sp, winResp);
    b = mu_calFR(sp, winBase);
    if isempty(r) || isempty(b), continue; end
    frR(c) = mean(r);
    frB(c) = mean(b);

    d = r - b;
    bs = mu.bootstrp(nBoot, @mean, d, 'seed', seed);
    br(c) = min(sum(bs < 0), sum(bs > 0)) / numel(bs);

    [latency, ~, ~, idx] = mu.calLatencyDual(sp, winResp, winBase, winBase, ...
        latTh, latNStart, latTTh, latMin);
    lat(c) = mu.ifelse(isempty(latency), NaN, latency);
    latIdx(c) = idx;

    hFR = frR(c) > minSpkTrial * 1000 / diff(winResp);
    hC(c) = (br(c) < bootRatio) && (idx ~= 0) && hFR;
end

h = any(hC(condIdx));
info = struct('h', hC, 'bootRatio', br, 'frResp', frR, 'frBase', frB, ...
    'latency', lat, 'latIndex', latIdx);

return;
end

function [bRes, ci] = bootstrp(nboot, bootfun, data, varargin)
%BOOTSTRP  Bootstrap resampling over trials.
%
% [bRes, ci] = mu.bootstrp(nboot, bootfun, data, 'Name', Value, ...)
%
% Input
%   nboot   : number of resamples (default 1000)
%   bootfun : function handle applied to ONE resample, e.g. @mean
%   data    : numeric vector or matrix (rows = trials), or a cell array of
%             per-trial data (then [bootfun] receives the resampled cell)
%
% Options
%   'seed'  : non-negative integer for a private stream; [] (default) uses
%             the global RNG, so results follow the caller's rng state
%   'alpha' : 0.05 -> percentile CI = [alpha/2, 1 - alpha/2]
%
% Output
%   bRes    : nboot x 1 bootstrap distribution
%   ci      : 2 x 1 percentile confidence interval
%
% Notes
%   - A private RandStream is used when 'seed' is given, so the global RNG
%     state is NOT advanced. This is what makes H_change reproducible
%     (the reference project's mBootstrp used the global bootstrp and was
%     therefore not reproducible across runs).
%   - If [bootfun] returns a non-scalar, only its first element is kept.
%
% See also mu.isChangeResp, mu.isOnsetResp.

narginchk(1, inf);
if nargin < 2 || isempty(bootfun), bootfun = @mean; end
if nargin < 3 || isempty(data), error('mu.bootstrp:noData', 'data is empty.'); end
if nargin < 1 || isempty(nboot), nboot = 1000; end

opt = mu.nv2struct(varargin);
seed = mu.getor(opt, 'seed', []);
alpha = mu.getor(opt, 'alpha', 0.05);

if iscell(data)
    n = numel(data);
    resample = @(idx) data(idx);
else
    if isvector(data), data = data(:); end
    n = size(data, 1);
    resample = @(idx) data(idx, :);
end

if isempty(seed)
    s = RandStream.getGlobalStream();
else
    s = RandStream('mt19937ar', 'Seed', seed);
end

bRes = zeros(nboot, 1);
for i = 1:nboot
    idx = randi(s, n, n, 1);
    v = bootfun(resample(idx));
    bRes(i) = v(1);
end

ci = quantile(bRes, [alpha / 2, 1 - alpha / 2])';

return;
end

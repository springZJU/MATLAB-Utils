function [h, info] = isOnsetResp(trials, varargin)
%ISONSETRESP  Onset-response flag (H_on) — RAT_LocalGlobal criterion.
%
% [h, info] = mu.isOnsetResp(trials, 'Name', Value, ...)
%
% Input
%   trials : cell array (nCond x 1); trials{c} is a cell array of per-trial
%            spike times (ms) aligned to the onset point.
%
% Options
%   'condIdx' : conditions that must ALL pass (default 1:numel(trials))
%   'winResp' : response window, ms (default [0 120])
%   'winBase' : baseline window, ms (default [-200 0])
%   'alpha'   : one-tailed alpha (default 0.01)
%   'minFR'   : minimum response rate, Hz (default 10)
%   'tail'    : 'right' (default) / 'left' / 'both'
%
% Output
%   h    : logical scalar, true when every condition in 'condIdx' passes
%   info : struct with .h (per condition), .p, .frResp, .frBase
%
% Criterion (per condition c), same as the reference buildNeuronSet.m:
%   p  = one-tailed t-test of per-trial FR in winResp vs winBase
%   hc = p < alpha  AND  mean(FR_resp) > mean(FR_base)  AND  mean(FR_resp) > minFR
%   H_on = all(hc(condIdx))
%
% The reference project applied this to the two pure-click conditions
% (condIdx = [1 9] for Reg4-5 / Reg5-4, i.e. 4 ms and 5 ms trains) and
% required BOTH to pass.
%
% See also mu.isChangeResp, mu_calFR, mu.ttest.

narginchk(1, inf);
nCond = numel(trials);
opt = mu.nv2struct(varargin);
condIdx = mu.getor(opt, 'condIdx', 1:nCond);
winResp = mu.getor(opt, 'winResp', [0 120]);
winBase = mu.getor(opt, 'winBase', [-200 0]);
alpha = mu.getor(opt, 'alpha', 0.01);
minFR = mu.getor(opt, 'minFR', 10);
tail = mu.getor(opt, 'tail', 'right');

hC = false(nCond, 1);
pv = nan(nCond, 1);
frR = nan(nCond, 1);
frB = nan(nCond, 1);
for c = 1:nCond
    sp = trials{c};
    if isempty(sp), continue; end
    r = mu_calFR(sp, winResp);
    b = mu_calFR(sp, winBase);
    if isempty(r) || all(isnan(r)) || isempty(b) || all(isnan(b)), continue; end
    frR(c) = mean(r);
    frB(c) = mean(b);
    % 用 MATLAB 内建 ttest 取 h（单尾方向判定与参考实现完全一致）；
    % mu.ttest 只返回 p，且内部 bf.ttest 在退化数据上会报 integral 警告。
    [hT, p] = ttest(r, b, 'Alpha', alpha, 'Tail', tail);
    pv(c) = p;
    hC(c) = (hT == 1) && (frR(c) > minFR);   % NaN -> false
end

h = all(hC(condIdx));
info = struct('h', hC, 'p', pv, 'frResp', frR, 'frBase', frB);

return;
end

function mu_export_one(bdfFolder, saveFolder, opts)
% 单录制导出（可调用 private\mu_preprocess_Neuracle）
% 输入：
%   bdfFolder  - 含 data.bdf / evt.bdf / 2024.mat 的文件夹
%   saveFolder - 输出文件夹（写入 data.mat 与 ICA res.mat）
%   opts       - mu_preprocess_configEEG(...) 的参数结构
% 说明：ICAPATH 指向 saveFolder（需事先把已有 ICA res.mat 放进去），
%       从而复用同一 ICA 解混矩阵，不重跑 runica。

if ~isfolder(saveFolder), mkdir(saveFolder); end
[trialsEEG, trialAll, fs, comp, speed] = mu_preprocess_Neuracle(bdfFolder, opts);
window = opts.window;
badChs = comp.badChs;
save(fullfile(saveFolder, "ICA res.mat"), "comp");
save(fullfile(saveFolder, "data.mat"), "trialAll", "trialsEEG", "speed", "window", "badChs", "fs");
end

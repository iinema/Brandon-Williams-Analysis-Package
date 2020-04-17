%% Modified cellReg script, combination of Alex's and Emmmanuel's 

function alignNwiseSessions2020(path,nFold)
    if nargin < 2 | isempty(nFold)
        nFold = 2;
    end
    oldcd = pwd;
    cd(path);
    paths = getFilePaths(path,'.mat')
    for i = length(paths):-1:1
        if contains(paths{i},'OriginalFiles')
            paths(i) = [];
        end        
    end
    
    iters = 5;
    
    warning ('off','all');
    
    clc
    fprintf('\n')
    %%% Reliability constaint
    
    %% Split by animal
    piece = [];
    ag = [];
    spiece = [];
    for i = 1:length(paths)
        ind = find(ismember(paths{i},'/'),1,'last')-1;
        piece = [piece; {paths{i}(1:ind)}];
        spiece = [spiece; {paths{i}(ind+2:end-4)}];
    end
    upiece = unique(piece);
    
    for mi = 1:length(upiece)
        fprintf(['\n\tMouse:  ' num2str(upiece{mi}) '\n'])
        
        isM = find(ismember(piece,upiece(mi)));
        sessions = paths(isM);      
        sessionnew = sessions;
        for i = 1 : length(sessions)
            num = 1;
            notnum = true;
            while notnum
                if ~isempty(str2num(sessions{i}(end-3-num:end-4)))
                    snum = str2num(sessions{i}(end-3-num:end-4));
                    num = num+1;
                else
                    notnum = false;
                end
            end
            sessionnew{snum} = sessions{i};
        end
        sessions = sessionnew;
        combs = nchoosek(1:length(sessions),nFold);

%         %%% Sliding temporal window
%         combs = repmat(1:length(sessions),[length(sessions) 1]);
%         for i = 1:length(sessions)
%             combs(i,:) = circshift(combs(i,:),[0 -(i-1)]);
%         end
%         combs(end-nFold+2:end,:) = [];
%         combs = combs(:,1:nFold);
       
        allPrepped = repmat({[]},[1 length(sessions)]);
        for si = 1:length(sessions)
            fprintf(['\t\tSession:  ' sessions{si}(find(ismember(sessions{si},'/'),1,'last')+1:end) '\n'])            
            ref = load(sessions{si});%,'calcium','processed');
            if isfield(ref,'ms')
                ref.calcium = ref.ms;
            end
            prepped = ref.calcium.SFPs .* bsxfun(@gt,ref.calcium.SFPs,0.5.*nanmax(nanmax(ref.calcium.SFPs,[],1),[],2));            
            [cellmap,exclude] = msExtractSFPsCellReg2020(prepped);
            outofFOV.cellmap{si} = cellmap;
            outofFOV.exclude_outofFOV{si} = exclude;
            allPrepped{si} = permute(prepped,[3 1 2]); %msExtractSFPs(ref.calcium);
            if isfield(ref,'processed')
                if isfield(ref.processed,'exclude')
                    exclude(find(ref.processed.exclude.SFPs) == 0) = 0;
                    outofFOV.exclude_badSFP = ref.processed.exclude.SFPs;
                end
            end
            allPrepped{si} = allPrepped{si}(exclude,:,:);
            outofFOV.exclude_all{si} = exclude;
            if si == 1
                ref = load(sessions{si},'alignment');
                if nFold == 2
                    oldAlignmentMap = repmat({[]},[length(isM) length(isM)]);
                else
                    oldAlignmentMap = repmat({[]},[length(combs(:,1))]);
                end
                if isfield(ref,'alignment')
                    alignID = help_getAlignmentID(ref.alignment,nFold,paths(isM));
                    if ~isnan(alignID)
                        oldAlignmentMap = ref.alignment(alignID).alignmentMap;
                    end
                end
            end
        end
        
        mspiece = spiece(isM);
        alignmentMap = repmat({[]},[length(combs(:,1)) 1]);
        probMap = alignmentMap;
        scoreMap = alignmentMap;
        cormat = diag(max(max(combs)));        
        for i = 1:length(combs(:,1))
            
            itermap = repmat({[]},[1 iters]);
            iterstruct = repmat({[]},[1 iters]);
            for si = combs(i,:)              
                prepped = allPrepped{si};
                outP = [upiece{mi} '\Segments\' mspiece{si}];% num2str(find(si == combs(i,:)))];                
                checkP(outP)
                save(outP,'prepped'); 
            end

            for iteration = 1:iters
                try
                    [map, regStruct] = registerCells2020([upiece{mi} '\Segments' ]);
                catch
                    map = [];
                    regStruct = [];
                end
                itermap{iteration} = map;
                iterstruct{iteration} = regStruct;
                close all
                close all hidden
                drawnow
            end
            try
                rmdir([upiece{mi}, '\Segments' ],'s');
            end
            iterstruct = iterstruct(~cellfun(@isempty,itermap));
            itermap = itermap(~cellfun(@isempty,itermap));
            
            [a, b] = nanmin(cellfun(@length,itermap));
%             [a b] = nanmax(scores);
            if ~isempty(b)
                map = itermap{b};
                score = iterstruct{b}.cell_scores;
                corval = iterstruct{b}.maximal_cross_correlation;
                for s = 1 : length(iterstruct{b}.p_same_registered_pairs)
                    probtemp(s,:) = nanmean(iterstruct{b}.p_same_registered_pairs{s});
                end
%                 corval = iterstruct{b}.maximal_cross_correlation;
            end
            alignmentMap{i} = map;            
            prob{i} = probtemp;
            scoreMap{i} = score;
            cormat(i) = corval;
            probtemp = [];
        end
        if nFold == 2
            nm = repmat({[]},length(sessions));
            nmp = repmat({[]},length(sessions));
            nms = repmat({[]},length(sessions));
            nmc = repmat({[]},length(sessions));
            for i = 1:length(combs(:,1))
                best = [alignmentMap(i) oldAlignmentMap(combs(i,1),combs(i,2))];
                best = best(~cellfun(@isempty,best));
                bprob = [prob(i) oldAlignmentMap(combs(i,1),combs(i,2))];
                bprob = bprob(~cellfun(@isempty,bprob));
                bestscore = [scoreMap(i) oldAlignmentMap(combs(i,1),combs(i,2))];
                bcorr = [cormat(i) oldAlignmentMap(combs(i,1),combs(i,2))];
                bestscore = bestscore(~cellfun(@isempty,bestscore));
                if isempty(best)
                    continue
                end
                [a b] = nanmin(cellfun(@length,best));
                nm{combs(i,1),combs(i,2)} = best{b};
                nmp{combs(i,1),combs(i,2)} = bprob{b};
                nms{combs(i,1),combs(i,2)} = bestscore{b};
                nmc{combs(i,1),combs(i,2)} = bcorr{b};
            end
            alignmentMap = nm;
            probMap = nmp;
            scoreMap = nmp;
            CorrMap = nmc;
        else
            nm = repmat({[]},[length(combs(:,1)) 1]);
            nmp = repmat({[]},[length(combs(:,1)) 1]);
            nms = repmat({[]},[length(combs(:,1)) 1]);
            nmc = repmat({[]},[length(combs(:,1)) 1]);
            for i = 1:length(combs(:,1))
                best = [alignmentMap(i) oldAlignmentMap(i)];
                best = best(~cellfun(@isempty,best));
                bprob = [prob(i) oldAlignmentMap(i)];
                bprob = bprob(~cellfun(@isempty,bprob));
                bestscore = [scoreMap(i) oldAlignmentMap(i)];
                bestscore = bestscore(~cellfun(@isempty,bestscore));
                bcorr = [cormat(i) oldAlignmentMap(i)];
                if isempty(best)
                    continue
                end
                [a b] = nanmin(cellfun(@length,best));
                nm{i} = best{b};
                nmp{i} = bprob{b};
                nms{i} = bestscore{b};
                nmc{i} = bcorr{b};
            end
            alignmentMap = nm;
            probMap = nmp;
            scoreMap = nms;
            CorrMap = nmc;
        end
        
        ref = load(sessions{1});
        if isfield(ref,'alignment')
            doInd = help_getAlignmentID(ref.alignment,nFold,paths);
            if isnan(doInd)
                doInd = length(ref.alignment)+1;
            end
        else
            doInd = 1;
        end        
        Singlemap = ReorganizeAlignmentMap(alignmentMap);
        [Singlemap, avg_psame] = ElimConflict2020(Singlemap,alignmentMap,scoreMap);
        Singlemap = FindMissingCells2020(Singlemap,outofFOV);
        
        ref.alignment(doInd).alignmentMap = alignmentMap;
        ref.alignment(doInd).Singlemap = Singlemap;
        ref.alignment(doInd).combs = combs;
        ref.alignment(doInd).sessions = sessions;
        ref.alignment(doInd).nFold = nFold;
        ref.alignment(doInd).probMap = probMap;
        ref.alignment(doInd).scoreMap = scoreMap;
        ref.alignment(doInd).CorrMap = CorrMap;
%         save('temporaryAlignmentMap','alignmentMap')
        save(sessions{1},'-struct','ref','-v7.3');
    end
end
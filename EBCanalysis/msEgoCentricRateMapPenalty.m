function [out, detailed]= msEgoCentricRateMapPenalty(ms,HD,tracking, frameMap, pixX, pixY, binarize, varargin)
%%Egocentric Boundary Cell Rate Map function,boundary location polar plots
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%This function will take your data and analize it in a way to facilitate  %
%Egocentric Boundary Cell(EBC) identification. Inputs as marked above     %
%are:["ms.mat" file containing all of the physiology data, the Head       %
%Direction matrix, Head position matrix, frameMap matrix, user defined    %
%threshold (typically 0.1), x-axis pixel to cm conversion factor, and     %
%y-axis pixel to cm factor(may vary depending on video quality). varargin %
%can be ignored.                                                          %
%This function will create a new folder within you directory called "EBC  %
%results" and save all analysis figures as numbered JPG pictures in said  %
%folder.                                                                  %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%Author Emmanuel Wilson, modified from Jake Hinman
warning('off','stats:glmfit:IterationLimit');
warning('off','curvefit:fit:noStartPoint');
warning('off','curvefit:fittype:sethandles:WeibullxMustBePositive');
warning('off','stats:glmfit:BadScaling');
warning('off','MATLAB:nargchk:deprecated');

FOVsize = 30;
name = 'EBCresultsContinuousReliabilityNotSmooth1Deg';

%% Setup & Parse
p = inputParser;
p.addParameter('videoSamp', 1);                    % calculate every X frames of video
p.addParameter('degSamp', 1);                      % Degree bins
p.addParameter('heading', 1);                       % use heading (0--> Head direction)
p.addParameter('ifVideo', 0);                       % Play the video?
p.addParameter('labels', 1);                        % Plot forward?
p.addParameter('distanceBins', 0:1:38);           % How far to look (cm)
p.addParameter('boundaryMode', 1);                  % 0-> autolines, 1-> click, mat->useit
p.addParameter('ifLine', 0);
p.addParameter('figures',[0 0 0 1 1 1 1 1]);
p.addParameter('mergeFigures',1);                   % if 1 then puts in single figure
p.addParameter('smooth', [5 5 5])
p.parse(varargin{:});

%% Get behavior information
ratemaps = zeros(FOVsize,361,length(ms.FiltTraces(1,:)));        %Probability ratemap values
ms.ind_fire = NaN(ms.numFrames,length(ms.FiltTraces(1,:))); %Indices of neuron activity/firing
ms.cell_x = NaN(ms.numFrames,length(ms.FiltTraces(1,:)));   %X coordinate of locations where cell fired
ms.cell_y = NaN(ms.numFrames,length(ms.FiltTraces(1,:)));   %Y cooridnates of locations where cell fired
ms.cell_time = NaN(ms.numFrames,length(ms.FiltTraces(1,:)));%Time at when cell fired
degBins = (-180:2:179);                                  %Angle bins for EBC metric polar plot
degBins = degBins';                                     %reorient bins
degBins = deg2rad(degBins);                             %Convert to radians
freqFire = zeros(1,length(ms.FiltTraces(1,:)));             %Firing frequency for each cell
mrall = freqFire;                                       %MRL for each cell
freqMax = freqFire;                                     %Max frequency of each cell
ms.HDfiring = ms.ind_fire;                              %Indices of neuron activity for head direction
distanceBins = 0:1:FOVsize;                                  %set to look at half the length of the field which in our case is ~38cm (37.5 rounded up)
mkdir(name)                         %Create new folder within current directory
mrtot = 0;                                              %total MRL
counter = 0 ;                                           %counter
fps = 30;                                               %Frames per second
spf = 1/fps;                                            %Seconds per frame
ms.timestamp = frameMap.*spf;                           %time stamp in seconds

if length(frameMap)> length(tracking(:,1))
    frameMap = frameMap(1:find(frameMap == length(tracking(:,1))));
    fprintf('FrameMap is larger than the behav')
end
%% Get structure of environment
%Identify where the bounds of the environment are located. Through a subfunction that allows the user to click
%on a plot of the positional data to indicate where the corners of the environment are located.

QP = findEdges(tracking);       %finds the edge of the graph and mark the boundaries
%% Calculate distances
degSamp = 1;                                                            %angle resolution
[dis, ex, ey] = subfunc(tracking(frameMap(:,1),1),tracking(frameMap(:,1),2),HD(frameMap), QP, degSamp);   %calls funtion to bring back wall distances when neuron fired
dis_raw = dis;
dis = fillmissing(dis,'pchip',2);                                          %interpolates missing values
% [a1 a2] = find(dis<0);
% dis(a1,:) = nan;
dis = dis*pixX;                                                             %Converts boundary distances from pixels to cm.
dis = circshift(dis,90,2);                                                  %shifts values by 90 degrees

if frameMap(length(frameMap)) < length(ms.FiltTraces)
    ms.FiltTraces = ms.FiltTraces(frameMap);   %Sink trace if not already sinked    
end
firePeaks = Binarize(ms);
%Loop through every cell, extract and analize firing instances and boundary locations
for cellNum = 43: length(ms.FiltTraces(1,:))
    if binarize == 1
        firing = firePeaks.binarizedTraces(:,cellNum);%ms.FiltTraces(:,cellNum);%ms.firing(:,cellNum);                          %Extract firing trace
        firing = circshift(firing,-6,1);
        firing(end-6 : end, :) = 0;
    else
        firing = ms.FiltTraces(:,cellNum);
    end
    fire = firing;                                  %Duplicate
    if min(fire)<0
        fire = fire + abs(min(fire));      
    else
        fire = fire - min(fire);
    end
    ifire = find(fire);                                     %Find indices for all non-zero values 
    if(~isempty(ifire))
        for j = 1 : length(ifire)
            ms.ind_fire(j,cellNum) = ifire(j);                      %Add firing index to ms struct
            ms.cell_x(j,cellNum) = tracking((frameMap(ifire(j))));  %X postion of mouse during firing at sinked time
            ms.cell_y(j,cellNum) = tracking((frameMap(ifire(j))),2);%Y position of mouse during firing at sinked time
            ms.cell_time(j,cellNum) = ms.timestamp(ifire(j));       %Physiological time of firing
            ms.HDfiring(j,cellNum) = HD(frameMap(ifire(j)));        %Head Direction of mouse at time of neural firing
        end                     
        %% Calculate raw maps:
        thetaBins = deg2rad(linspace(-180,180,361));                    %angle bins  MODIFICATION: size(dis,2) -> 120
        occ = NaN(length(thetaBins), length(distanceBins));                     %wall occupancy bins
        nspk = occ;                                                             %Number of spikes bins
        distanceBins(end+1) = Inf;                                              %Adds an Infinity value at the end of the bins as safety procaution/break point
        ci = ms.ind_fire(:,cellNum);                                            %firing instances of the cell
        for i = 1:length(thetaBins)
            t = dis(:,i); %boundary distance for a particular bin  for 3deg bins try (:,i*3-2:i*3)
            for k = 1:length(distanceBins)-1
                inds = t>=distanceBins(k) & t<distanceBins(k+1);                %filter through the boundary distances
                inds = sum(inds,2);
                occ(i,k) = sum (inds);                                          %Wall occupancy definition
                inds = find(inds);                                              %find all non-zero boundary distances indices
                [nspk(i,k)] = sum(fire(intersect(inds,ci)));                      %Number of spike instances definition
%                 nspk(i,k) = nspk(i,k) - 0.1*(length(inds)) ;
            end
        end
        distanceBins = distanceBins(1:end-1);                                   %itteration through bins
%         if any(nspk(:)>0)
            counter = counter + 1;
            %max frequency
            tempcount = 0;
            tempmax = 0;
            for it = 1 : length(ms.FiltTraces(:,1))
                if fire(it,1) > 0
                    tempcount = tempcount +1;
                end
                if mod(it,30) == 0
                    if tempmax < tempcount
                        tempmax = tempcount;
                    end
                    tempcount = 0;
                end
                freqMax(1,cellNum) = tempmax;
            end
            
            % bring back to original dims
            occ = occ(:,1:end-1); occ=occ';
%             cutout = find(occ<100);
%             occ(cutout) = 1;
            nspk = nspk(:,1:end-1); nspk=nspk';
%             nspk = nspk - min(nspk(:));
            rm = (nspk./occ);            
            
            rm(find(isnan(rm))) = min(rm(:));
            rm(find(isinf(rm))) = min(rm(:));
%             rm(cutout) = 0;
%             rm = rm - min(rm(:));
            
            
            %% Smoothing
%             occ = [occ occ occ];
%             nd = numel(thetaBins);
%             occ = CMBHOME.Utils.SmoothMat(occ, smooth(1:2), smooth(3));
%             occ = occ(:, nd+1:2*nd);
% %             occ(cutout) = 0;
%             
%             nspk = [nspk nspk nspk];
%             nspk = CMBHOME.Utils.SmoothMat(nspk,smooth(1:2),smooth(3));   % Smooth it
%             nspk = nspk(:,nd+1:2*nd); % bring it back
%             
%             rm = (nspk./occ);
%             rm(find(isnan(rm))) = min(rm(:));
%             rm(find(isinf(rm))) = min(rm(:));
% %             rm = rm - min(rm(:));
%             rm = [rm rm rm];
%             rm = CMBHOME.Utils.SmoothMat(rm,smooth(1:2),smooth(3));   % Smooth it
%             rm = rm(:,nd+1:2*nd); % bring it back
%             
%             
%             occ = fliplr(occ);
%             nspk = fliplr(nspk);
%             rm = fliplr(rm);
            
            %% Plots
            %The first three plots are rectangular versions of the three color-coded plots
            %Figure 7 is part of our work in progress for estimating a cell�s preferred distance.
            %Finally, figure 8 is a trajectory plot with heading color coded spike dots
            %distanceBins=distanceBins+1;
            %load ratImage;

            figure(1);
            n=2;
            c = 1;
            % Occupancy square
            subplot(n,4,c);c=c+1;
            imagesc(thetaBins,distanceBins,occ);
            set(gca,'YDir','Normal'); colormap(jet);
            freezeColors
            title('Occ')
            colorbar
            
            % nspk square
            subplot(n,4,c);c=c+1;
            imagesc(thetaBins,distanceBins,nspk);
            set(gca,'YDir','Normal'); colormap(jet)
            freezeColors
            title('nspk')
            colorbar
            
            % rm square
            subplot(n,4,c);c=c+1;
            imagesc(thetaBins,distanceBins,rm);
            set(gca,'YDir','Normal'); colormap(jet);
            freezeColors
            title('rm');
            colorbar
            
            % occupancy circular
            subplot(n,4,c);c=c+1;
            % the +pi/2 brings "forwards" to "up"
            [t2, r2] = meshgrid(wrapTo2Pi(thetaBins+pi/2), distanceBins(1:end-1));
            [x, y] = pol2cart(t2,r2);
            surface(x,y, occ), shading interp
            hold on
            set(gca,'XTick',[],'YTick',[])
            axis square
            colormap(jet)
%             set(gca, 'YDir','Normal','CLim',[0 prctile(occ(:),99)])
            set(gca,'YDir','Normal')
            freezeColors
            title('occ')           
            
            % nspk circular
            subplot(n,4,c);c=c+1;
            % the +pi/2 brings "forwards" to "up"
            [t2, r2] = meshgrid(wrapTo2Pi(thetaBins+pi/2), distanceBins(1:end-1));
            [x, y] = pol2cart(t2,r2);
            surface(x,y, nspk), shading interp
            hold on
            set(gca,'XTick',[],'YTick',[])
            axis square
            title([])
            colormap(jet)
%             set(gca, 'YDir','Normal','CLim',[0 prctile(nspk(:),99)])
            set(gca,'YDir','Normal')
            freezeColors
            title('nspk')
            
            % ratemap circular
            subplot(n,4,c);c=c+1;
            % the +pi/2 brings "forwards" to "up"
            [t2, r2] = meshgrid(wrapTo2Pi(thetaBins+pi/2), distanceBins(1:end-1));
            [x, y] = pol2cart(t2,r2);
            h=surface(x,y, rm); shading interp
            
            %         set(h, 'AlphaData', occ>=30)
            %         set(h,'FaceAlpha','interp')
            
            hold on
            set(gca,'XTick',[],'YTick',[])
            axis square
            colormap(jet)
%             set(gca, 'YDir','Normal','CLim',[0 prctile(rm(:), 99)])
            set(gca,'YDir','Normal')
            freezeColors
            title('rm')
            
            %Trajectory map
            if binarize == 1
                subplot(n,4,c);c=c+1;
                edg = splitter(QP);
                hold on
                plot(pixX*tracking(:,1),-pixY*tracking(:,2),'Color',[.7 .7 .7])
                colormap(hsv)
                xlim(pixX*[min(tracking(:,1)) max(tracking(:,1))]);ylim(pixY*[-max(tracking(:,2)) -min(tracking(:,2))])
                cx=pixX*ms.cell_x(:,cellNum);
                cy=pixY*ms.cell_y(:,cellNum);
                scatter(cx,-cy,38,ms.HDfiring(:,cellNum),'filled')
                set(gca,'YDir','Normal')
                caxis([0 360])
                title('Traj')
                axis off
                axis square
            else
                subplot(n,4,c);c=c+1;
                edg = splitter(QP);
                hold on
                plot(pixX*tracking(:,1),-pixY*tracking(:,2),'Color',[.7 .7 .7])
                colormap(hsv)
                xlim(pixX*[min(tracking(:,1)) max(tracking(:,1))]);ylim(pixY*[-max(tracking(:,2)) -min(tracking(:,2))])
                cx=pixX*ms.cell_x(:,cellNum);
                cy=pixY*ms.cell_y(:,cellNum);
                
                for scatobj = 1 : 5
                    perc = scatobj*20;
                    scatTrace = fire;
                    scatTrace(scatTrace> prctile(scatTrace,perc) | scatTrace<= prctile(scatTrace,(perc-20)))=0;
                    scatInd = find(scatTrace);
                    s=scatter(cx(scatInd),-cy(scatInd),38,ms.HDfiring(scatInd,cellNum),'filled');
                    s.MarkerFaceAlpha = (perc-20)*0.01;
                end                   
            end
            set(gca,'YDir','Normal')    
            caxis([0 360])
            title('Traj')
            axis off
            axis square

%             %EBC Metric
            avgcount = zeros(1,i);
            metric = zeros(1,180);
            subplot(n,4,c);
%             contour(rm)
            r = 0;
            for it = 1 : i
%                 metric(1,it) = mean(rm(:,it));
                avgcount(1,it) = mean(rm(:,it));
                if mod(it,2) == 0
                    r = it/2;
                    metric(1,r) = (avgcount(1,it-1)+avgcount(1,it))/2;
                end
            end
            metric = metric';
            if ~binarize
                metric = metric - min(metric);
            end
            polarplot(degBins,metric)

            xs = metric(1:end-1).*cos(degBins(1:end-1)); % average
            ys = metric(1:end-1).*sin(degBins(1:end-1));
            
            coordlims=axis;
            
            ang_hd = atan2(mean(ys),mean(xs)); % mean direction
            
            mr = (cos(ang_hd)*sum(xs) + sin(ang_hd)*sum(ys)) / sum(metric(1:end-1)); % mean resultant length
            
            mag_hd = sqrt(sum(ys)^2+sum(xs)^2)/sqrt(sum(abs(ys))^2+sum(abs(xs))^2)*6.28; % for visualizations sake

            hold on;
            polarplot([ang_hd ang_hd ],[0 mr], 'r')
            pol = gca;
            pol.ThetaZeroLocation = 'top';
            hold off
            title('Wall Directionality')
            stat = ['MRL: ' num2str(mr) 'Angle : ' num2str(rad2deg(ang_hd))];
            text(0.2,coordlims(4),stat);                           

            %Save Results
            saveas(gcf,[name,'/',num2str(cellNum),'EBC.jpg']); %saving figure as a picture file (.jpg) in the new folder "EBCresults"
            ms.ind_fire = NaN(ms.numFrames,length(ms.FiltTraces(1,:))); %Indices of neuron activity/firing
            ms.cell_x = NaN(ms.numFrames,length(ms.FiltTraces(1,:)));   %X coordinate of locations where cell fired
            ms.cell_y = NaN(ms.numFrames,length(ms.FiltTraces(1,:)));   %Y cooridnates of locations where cell fired
            ms.cell_time = NaN(ms.numFrames,length(ms.FiltTraces(1,:)));%Time at when cell fired
            ms.HDfiring = ms.ind_fire;                              %Indices of neuron activity for head direction 
            ratemaps(:,:,cellNum) = rm;
            mrtot = mrtot + mr;
            freqFire(1,cellNum) = length(ifire);
            mrall(1,cellNum) = mr;
            clf
%         end
    end
end
out.mravg = mrtot/counter;
out.mrall = mrall;
out.freqFire = freqFire;
out.freqMax = freqMax;
freqFire = freqFire/(length(frameMap(:,1))/30);
out.rm = ratemaps;
out.frameNum = length(frameMap(:,1));
out.QP = QP;
out.dis = dis;
save('EBCstats.mat','out');
histogram(freqFire)
title('average cell firing rate at 0.1 treshold')
ylabel('Number of Cells')
xlabel('frequency (Hz)')
savefig('Thresh0.1FreqHist.fig')
figure
histogram(mrall)
title('MRL distribution at 0.1 treshold')
ylabel('Number of Cells')
xlabel('Mean Resultant Length')
savefig('Thresh0.1_MRL_Hist.fig')
end

%% Subfunctions

%This function calculates the distance from the animal to boundaries of the environment at each behavioral data point.
%The distance calculation has to be done for all orientations around the animal centered on the animal�s
%current heading direction. That is to say that the animal�s current heading is always 0� and the distance
%to the boundaries is calculated for each of the 360 one-degree bins around the animal.
function [dis, ex, ey] = subfunc(rx,ry,hd, QP, degSamp)

mxd = sqrt((max(rx)-min(rx))^2 + (max(ry)-min(ry))^2);                  %sets bin radial maximum
degs = deg2rad(-180:degSamp:180);
hd = deg2rad(hd);

edg = splitter(QP);
edg = cell2mat(edg(:));
dis = NaN(numel(rx),size(edg,1), numel(degs));
dir = dis;

for i = 1:size(edg,1)
    x1=edg(i,1,1);x2=edg(i,1,2);
    y1=edg(i,2,1);y2=edg(i,2,2);
    
    for h = 1:numel(degs)
        hdof=degs(h);
        y3=ry;x3=rx;
        y4=ry+mxd*sin(hd+hdof);
        x4=rx+mxd*cos(hd+hdof);
        
        %https://en.wikipedia.org/wiki/Line%E2%80%93line_intersection#Intersection_of_two_lines
        px1 = (x1.*y2-y1.*x2).*(x3-x4) - (x1-x2).*(x3.*y4-y3.*x4);
        px2 = (x1-x2).*(y3-y4) - (y1-y2).*(x3-x4);
        px  = px1./px2;
        
        py1 = (x1.*y2-y1.*x2).*(y3-y4) - (y1-y2).*(x3.*y4-y3.*x4);
        py2 = (x1-x2).*(y3-y4) - (y1-y2).*(x3-x4);
        py = py1./py2;
        
        d = sqrt((ry-py).^2 + (rx-px).^2);
        dis(:,i,h) = d;
        
        % need to filter down to the right direction ...
        dir(:,i,h) = wrapToPi(atan2(py-ry,px-rx)-(hd+hdof));
        
        % oh ... we were allowing forever.... filter by bounding box
        bb = [min(QP(:,1)) max(QP(:,1)); min(QP(:,2)) max(QP(:,2))];
        % |xmin, xmax|
        % |ymin, ymax|
        indexes = ~(px>=bb(1,1) & px<=bb(1,2) & py>=bb(2,1) & py<=bb(2,2));
        dis(indexes,i,h) = NaN;
    end
    
end


dis(dis>mxd) = NaN;
dis(abs(dir)>pi/4) = NaN;

%% output
dis=squeeze(nanmin(dis,[],2));
for i = 1 :length(rx)
    if(rx(i)>max(edg(:,1,1)) || rx(i)<min(edg(:,1,1)) || ry(i)>max(edg(:,2,1)) || ry(i)<min(edg(:,2,1)))
        dis(i,:) = NaN;
    end
end
dd=repmat(degs,size(rx,1),1) + repmat(hd,1,numel(degs));
dx=dis.*cos(dd); dy=dis.*sin(dd);
ey=dy+repmat(ry,1,numel(degs));
ex=dx+repmat(rx,1,numel(degs));

end

%This subfunction will ask for the corner locations to determine the open
%field
function QP = findEdges(tracking)
ifEscape = 0;
h=figure();

while ~ifEscape
    figure(h);
    clf
    
    %[occupancy, xdim, ydim]=root.Occupancy([],[],1,2);
    %imagesc(xdim,ydim,occupancy');
    set(gca,'YDir','Normal'); %colormap(jet);
    clim=get(gca,'clim');set(gca,'clim',clim/50);
    hold on
    plot(tracking(:,1),tracking(:,2),'k');
    QP = [];
    
    set(h,'Name','Select Corners of Walls. Esc--> done. **Do not complete!**')
    
    button = 1;
    
    while button~=27
        [x,y,button] = ginput(1);
        
        clf
        
        %imagesc(xdim,ydim,occupancy');
        set(gca,'YDir','Normal'); %colormap(jet);
        clim=get(gca,'clim');set(gca,'clim',clim/50);
        hold on
        plot(tracking(:,1),tracking(:,2),'k');
        
        if ~isempty(QP)
            plot(QP(:,1),QP(:,2),'r')
            plot(QP(:,1),QP(:,2),'ro','MarkerFaceColor','r')
        end
        
        if button == 32 %space bar
            QP = [QP; NaN NaN];
        elseif button~=27
            QP = [QP; x y];
        end
        
        plot(QP(:,1),QP(:,2),'r')
        plot(QP(:,1),QP(:,2),'ro','MarkerFaceColor','r')
        
    end
    
    %Ask for verification
    edg = splitter(QP);
    clf;
    set(h,'Name','Verify. 0--> Try again; 1--> Confirm')
    plot(tracking(:,1),tracking(:,2),'k');
    hold on
    
    for m = 1:numel(edg)
        for n = 1:size(edg{m},1)
            sp = squeeze(edg{m}(n,:,1));
            ep = squeeze(edg{m}(n,:,2));
            plot([sp(1) ep(1)],[sp(2) ep(2)],'ro','MarkerFaceColor','r')
            plot([sp(1) ep(1)],[sp(2) ep(2)],'r')
        end
    end
    
    
    % set or repeat
    while button ~=48 && button~=49
        [~,~,button]=ginput(1);
    end
    ifEscape = button==49;
    
end

close(h);
drawnow();
end

%Split the corner coordinates in X and Y vectors
function edg = splitter(QP)

inds = find(isnan(QP(:,1)));
xs=CMBHOME.Utils.SplitVec(QP(:,1), @(x) isnan(x));
ys=CMBHOME.Utils.SplitVec(QP(:,2), @(x) isnan(x));

% split corners
for m = 1:size(xs,1)
    QP2{m} = [xs{m} ys{m}];
    QP2{m}(find(isnan(QP2{m}(:,1))),:) = [];
end

for m = 1:numel(QP2)
    for n = 1:size(QP2{m},1)
        sp = n;ep=n+1;
        if ep>size(QP2{m},1), ep=1;end
        edg{m}(n,:,1) = [QP2{m}(sp,1) QP2{m}(sp,2)];
        edg{m}(n,:,2) = [QP2{m}(ep,1) QP2{m}(ep,2)];
    end
end

end
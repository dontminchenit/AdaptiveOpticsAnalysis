
% Robert F Cooper 11-3-2015 10:40AM
%
% This software is responsible for the data processing of temporal
% datasets.
clear;
close all force;


profile_method = 'segmentation';
norm_type = 'prestim_sub';
cutoff = 0.8; % The percentage of time a cone must be stimulated relative to all stimulus in order to be included for analysis

% mov_path=pwd;
[ref_image_fname, mov_path]  = uigetfile(fullfile(pwd,'*.tif'));
ref_coords_fname = [ref_image_fname(1:end-4) '_coords.csv'];
stack_fnames = read_folder_contents( mov_path,'avi' );

for i=1:length(stack_fnames)
    if ~isempty( strfind( stack_fnames{i}, ref_image_fname(1:end - length('_AVG.tif') ) ) )
        temporal_stack_fname = stack_fnames{i};
        visible_stack_fname = strrep(temporal_stack_fname,'confocal','visible');
        break;
    end
end

%% Load the dataset(s)

ref_image  = double(imread(  fullfile(mov_path, ref_image_fname) ));
ref_coords = dlmread( fullfile(mov_path, ref_coords_fname));
temporal_stack_reader = VideoReader( fullfile(mov_path,temporal_stack_fname) );
if exist(fullfile(mov_path,visible_stack_fname),'file')
    visible_stack_reader = VideoReader( fullfile(mov_path,visible_stack_fname) );
end

i=1;
while(hasFrame(temporal_stack_reader))
    temporal_stack(:,:,i) = double(readFrame(temporal_stack_reader));
    if exist(fullfile(mov_path,visible_stack_fname),'file')
        visible_stack(:,:,i)  = readFrame(visible_stack_reader);
    else
        visible_stack(:,:,i)  = zeros(size(temporal_stack(:,:,i)));
    end
    i = i+1;
end

%% Find the frames where the stimulus was on, and create the stimulus
% "masks"
visible_signal = zeros(size(visible_stack,3),1);
for v=1:size(visible_stack,3)
    
    vis_frm = visible_stack(:,:,v);        
    
    visible_signal(v) = mean(vis_frm(:));
end

stim_locs = find( visible_signal > 10 );

% Make the masks where visible light fell (and was detected)
vis_masks = zeros(size(visible_stack,1), size(visible_stack,2), size(stim_locs,1)+1);

% The first frame recieves no stimulus
for i=1:size(stim_locs,1)
    
    vis_frm = visible_stack(:,:,stim_locs(i));        
%     figure(1); imagesc(vis_frm); colormap gray; axis image;       
    noise_floor = 4;
    vis_frm = vis_frm-min(vis_frm(:));
    vis_frm( vis_frm<=2*noise_floor ) = 0;
    vis_frm( vis_frm>2*noise_floor )  = 1;
    vis_masks(:,:,i+1) = imclose(vis_frm, strel('disk',9) );
%     figure(2); imagesc(vis_masks(:,:,i)); colormap gray; axis image; pause(0.01)
end

if ~isempty(stim_locs) % If there were stimulus frames, find them and set up the masks to use, as well as the normalization frames

    stim_mask = max(vis_masks,[],3);
    
    control_mask = ~stim_mask; % The control region is where no stimulus fell.
    
    vis_masks = sum(vis_masks,3);
    
    % Only take regions with more than 80% of the stimulus falling on it.
    vis_masks( vis_masks < cutoff*max(vis_masks(:)) ) = 0;
    
    stim_mask( vis_masks < cutoff*max(vis_masks(:)) ) = 0;

    
    
    
else % If there were no detected stimuli frames.
    
    stim_mask  = zeros( size(temporal_stack,1), size(temporal_stack,2) );
    stim_locs = size(temporal_stack,3)+1;
    vis_masks = [];
    control_mask = ~stim_mask;
    
end



%% Isolate individual profiles
ref_coords = round(ref_coords);

cellseg = cell(size(ref_coords,1),1);
cellseg_inds = cell(size(ref_coords,1),1);



wbh = waitbar(0,'Segmenting coordinate 0');
for i=1:size(ref_coords,1)

    waitbar(i/size(ref_coords,1),wbh, ['Segmenting coordinate ' num2str(i)]);
    
    
    switch( profile_method )
        case 'segmentation'
            roiradius = 8;
            
            if (ref_coords(i,1) - roiradius) > 1 && (ref_coords(i,1) + roiradius) < size(ref_image,2) &&...
               (ref_coords(i,2) - roiradius) > 1 && (ref_coords(i,2) + roiradius) < size(ref_image,1)


                roi = ref_image(ref_coords(i,2) - roiradius : ref_coords(i,2) + roiradius, ref_coords(i,1) - roiradius : ref_coords(i,1) + roiradius);

                polarroi = imcart2pseudopolar(roi,.25,2);

                [pad_roi, adj, rowcol]=segment_splitcell(polarroi);

                dg = digraph(adj);        

                shortpath = shortestpath(dg,sub2ind(size(pad_roi), 1, ceil(size(pad_roi,2)/3)), ...
                                            sub2ind(size(pad_roi), size(pad_roi,1), ceil(size(pad_roi,2)/3)) );

                cone_edge_pol = rowcol(shortpath,:);

                cone_edge_pol = cone_edge_pol((cone_edge_pol(:,1) > 3 & cone_edge_pol(:,1) < 360),:);
                
                [x,y] = pol2cart( cone_edge_pol(1:end,1)*pi/180 , ...
                                  cone_edge_pol(1:end,2)/4 );

                conv_inds = convhull(ceil(x),ceil(y));

                cellseg{i} = [x(conv_inds)+ref_coords(i,1), y(conv_inds)+ref_coords(i,2)];

                cellseg_mask = roipoly(ref_image, (cellseg{i}(:,1))+1, (cellseg{i}(:,2)));
                cellseg_mask = imerode(cellseg_mask, ones(3));
                cellseg_inds{i} = find(cellseg_mask~=0);
                
                ref_image(cellseg_inds{i})= 0;
            end
        case 'box'
            roiradius = 1;
            
            if (ref_coords(i,1) - roiradius) > 1 && (ref_coords(i,1) + roiradius) < size(ref_image,2) &&...
               (ref_coords(i,2) - roiradius) > 1 && (ref_coords(i,2) + roiradius) < size(ref_image,1)
           
                [R, C ] = meshgrid((ref_coords(i,2) - roiradius) : (ref_coords(i,2) + roiradius), ...
                                   (ref_coords(i,1) - roiradius) : (ref_coords(i,1) + roiradius));
           
                cellseg_inds{i} = sub2ind( size(ref_image), R, C );

                cellseg_inds{i} = cellseg_inds{i}(:);
                
                ref_image(cellseg_inds{i})= 0;
                
%                 figure(1); imagesc(ref_image); colormap gray; axis image;
                
            end
        case 'cross'
            roiradius = 2;
            
            if (ref_coords(i,1) - roiradius) > 1 && (ref_coords(i,1) + roiradius) < size(ref_image,2) &&...
               (ref_coords(i,2) - roiradius) > 1 && (ref_coords(i,2) + roiradius) < size(ref_image,1)
           
%                 roi = zeros( 2*roiradius+1, 2*roiradius+1 );                
%                 roi(roiradius+1,:) = ref_image( ref_coords(i,2) - roiradius : ref_coords(i,2) + roiradius, ref_coords(i,1) );
%                 roi(:,roiradius+1) = ref_image( ref_coords(i,2), ref_coords(i,1) - roiradius : ref_coords(i,1) + roiradius );                
%                 figure(1); imagesc(roi); axis image; colormap gray;
%                 pause(0.1);

                cellseg_inds{i} = sub2ind( size(ref_image), (ref_coords(i,2) - roiradius) : (ref_coords(i,2) + roiradius), repmat(ref_coords(i,1), [1 2*roiradius+1]) );
                
                cellseg_inds{i} = [cellseg_inds{i} sub2ind( size(ref_image), repmat(ref_coords(i,2), [1 2*roiradius+1]) , ref_coords(i,1) - roiradius : ref_coords(i,1) + roiradius) ];

                cellseg_inds{i} = cellseg_inds{i}(:);
                
                ref_image(cellseg_inds{i})= 0;
                
%                 figure(1); imagesc(ref_image); colormap gray; axis image;
            end
    end

end

%% Code for viewing the segmented/masked cones
colorcoded_im = repmat(ref_image,[1 1 3]);

max_overlap = max(vis_masks(:));
max_red_mult = max(ref_image(:))/max_overlap;
            
seg_mask = ref_image == 0;

if ~isempty( vis_masks )
                        
    colorcoded_im(:,:,1) = colorcoded_im(:,:,1) + (seg_mask.* (vis_masks.*max_red_mult));
    colorcoded_im(:,:,3) = colorcoded_im(:,:,3) + (seg_mask.* (control_mask.*max(ref_image(:))) );

else
    colorcoded_im(:,:,3) = colorcoded_im(:,:,3) + (seg_mask.* (control_mask.*max(ref_image(:))) );
end

figure(1); imagesc( uint8(colorcoded_im) ); axis image; 
imwrite(uint8(colorcoded_im), fullfile(mov_path, [ref_image_fname(1:end - length('_AVG.tif') ) '_stim_map.png' ] ) );



%% Extract the raw reflectance of each cell.
cellseg_inds = cellseg_inds(~cellfun(@isempty,cellseg_inds));

stim_cell_reflectance = cell( length(cellseg_inds),1  );
stim_cell_times = cell( length(cellseg_inds),1  );

control_cell_reflectance = cell( length(cellseg_inds),1  );
control_cell_times = cell( length(cellseg_inds),1  );

j=1;

if ~ishandle(wbh)
    wbh = waitbar(0, 'Creating reflectance profile for cell: 0');
end

for i=1:length(cellseg_inds)
    waitbar(i/length(cellseg_inds),wbh, ['Creating reflectance profile for cell: ' num2str(i)]);

    stim_cell_times{i} = 1:size(temporal_stack,3);
    control_cell_times{i} = 1:size(temporal_stack,3);
    
    stim_cell_reflectance{i}    = zeros(1, size(temporal_stack,3));
    control_cell_reflectance{i} = zeros(1, size(temporal_stack,3));
    
    j=1;
    for t=1:size(temporal_stack,3)
            
        stim_masked_timepoint = stim_mask.*temporal_stack(:,:,t);

        control_masked_timepoint = control_mask.*temporal_stack(:,:,t);
        
        if all( stim_masked_timepoint(cellseg_inds{i}) ~= 0 )
            stim_cell_reflectance{i}(t) = mean( stim_masked_timepoint(cellseg_inds{i}));% ./  mean(stim_norm_timepoint(cellseg_inds{i}) );            
        else
            stim_cell_reflectance{i}(t) = NaN;            
        end
        
        if all( control_masked_timepoint(cellseg_inds{i}) ~= 0 )
            control_cell_reflectance{i}(t) = mean( control_masked_timepoint(cellseg_inds{i}));% ./  mean(control_masked_norm_timepoint(cellseg_inds{i}) );
        else            
            control_cell_reflectance{i}(t) =  NaN;
        end
    end

end
close(wbh);

%% Normalize the intensities of each cone to the average value of the control cones
c_cell_ref = cell2mat(control_cell_reflectance);
c_cell_ref = c_cell_ref( ~all(isnan(c_cell_ref),2), :);

s_cell_ref = cell2mat(stim_cell_reflectance);
s_cell_ref = s_cell_ref( ~all(isnan(s_cell_ref),2), :);

for t=1:size(c_cell_ref,2)
    c_ref_mean(t) = mean(c_cell_ref( ~isnan(c_cell_ref(:,t)) ,t));    
end

% plot(c_ref_mean,'b'); hold on; plot(s_ref_mean,'r'); hold off;

norm_stim_cell_reflectance = cell( size(stim_cell_reflectance) );

for i=1:length( stim_cell_reflectance )
    norm_stim_cell_reflectance{i} = stim_cell_reflectance{i}./c_ref_mean;
    
    no_ref = ~isnan(norm_stim_cell_reflectance{i});
    
    norm_stim_cell_reflectance{i} = norm_stim_cell_reflectance{i}(no_ref);    
    stim_cell_times{i}            = stim_cell_times{i}(no_ref);
%     plot( stim_cell_times{i}, norm_stim_cell_reflectance{i} ); hold on;
end

norm_control_cell_reflectance = cell( size(control_cell_reflectance) );

for i=1:length( control_cell_reflectance )
    
    norm_control_cell_reflectance{i} = control_cell_reflectance{i}./c_ref_mean;
    
    no_ref = ~isnan(norm_control_cell_reflectance{i});
    norm_control_cell_reflectance{i} = norm_control_cell_reflectance{i}(no_ref);
    control_cell_times{i}       = control_cell_times{i}(no_ref);
    
%     plot( control_cell_times{i}, norm_control_cell_reflectance{i},'b'); hold on;
end


if ~isempty( strfind(norm_type, 'prestim'))
    % Then normalize to the average intensity of each cone BEFORE stimulus.
    for i=1:length( norm_stim_cell_reflectance ) % STIM

        prestim_mean = mean( norm_stim_cell_reflectance{i}(stim_cell_times{i}<stim_locs(1) & ~isnan( norm_stim_cell_reflectance{i} )) );

        norm_stim_cell_reflectance{i} = norm_stim_cell_reflectance{i}./prestim_mean;
    end
    for i=1:length( norm_control_cell_reflectance ) % CONTROL

        prestim_mean = mean( norm_control_cell_reflectance{i}( control_cell_times{i}<stim_locs(1) & ~isnan( norm_control_cell_reflectance{i} ) ) );

        norm_control_cell_reflectance{i} = norm_control_cell_reflectance{i}./prestim_mean;

    end
    
elseif ~isempty( strfind(norm_type, 'poststim'))
    % Then normalize to the average intensity of each cone AFTER stimulus.
    for i=1:length( norm_stim_cell_reflectance ) % STIM

        prestim_mean = mean( norm_stim_cell_reflectance{i}(stim_cell_times{i}>stim_locs(end) & ~isnan( norm_stim_cell_reflectance{i} )) );

        norm_stim_cell_reflectance{i} = norm_stim_cell_reflectance{i}./prestim_mean;
    end
    for i=1:length( norm_control_cell_reflectance ) % CONTROL

        prestim_mean = mean( norm_control_cell_reflectance{i}( control_cell_times{i}>stim_locs(end) & ~isnan( norm_control_cell_reflectance{i} ) ) );

        norm_control_cell_reflectance{i} = norm_control_cell_reflectance{i}./prestim_mean;

    end    
elseif ~isempty( strfind(norm_type, 'meanall'))
    % Then normalize to the average intensity of each cone's average value.
    for i=1:length( norm_stim_cell_reflectance ) % STIM

        prestim_mean = mean( norm_stim_cell_reflectance{i}(~isnan( norm_stim_cell_reflectance{i} )) );

        norm_stim_cell_reflectance{i} = norm_stim_cell_reflectance{i}./prestim_mean;
    end
    for i=1:length( norm_control_cell_reflectance ) % CONTROL

        prestim_mean = mean( norm_control_cell_reflectance{i}( ~isnan( norm_control_cell_reflectance{i} ) ) );

        norm_control_cell_reflectance{i} = norm_control_cell_reflectance{i}./prestim_mean;
    end
else
    
end


% i=1;
% while i<length( norm_control_cell_reflectance )
%     if any( norm_control_cell_reflectance{i} > 2.2)        
%         norm_control_cell_reflectance = norm_control_cell_reflectance([1:i-1 i+1:end]);
%         control_cell_times = control_cell_times([1:i-1 i+1:end]);
%     else
%         i=i+1;
%     end    
% end

%% Pooled variance of all cells before first stimulus
[ ref_stddev_stim ]    = reflectance_pooled_variance( stim_cell_times,    norm_stim_cell_reflectance,    size(temporal_stack,3) );
[ ref_stddev_control ] = reflectance_pooled_variance( control_cell_times, norm_control_cell_reflectance, size(temporal_stack,3) );

% If its in the normalization, subtract the control value from the stimulus
% value
if ~isempty( strfind(norm_type, 'sub') )
    ref_stddev_stim    = ref_stddev_stim-ref_stddev_control;
    ref_stddev_control = ref_stddev_control-ref_stddev_control;
end
hz=16.6;
figure(10); hold off;

plot( (1:length(ref_stddev_stim))/hz,ref_stddev_stim,'r'); hold on;
plot( (1:length(ref_stddev_control))/hz,ref_stddev_control,'b'); hold on;
legend('Stimulus cones','Control cones');
plot(stim_locs/hz, max([ref_stddev_stim; ref_stddev_control])*ones(size(stim_locs)),'r*'); hold off;
ylabel('Standard deviation'); xlabel('Time (s)'); title( strrep( [ref_image_fname(1:end - length('_AVG.tif') ) '_' profile_method '_stddev_ref_plot' ], '_',' ' ) );
saveas(gcf, fullfile(mov_path, [ref_image_fname(1:end - length('_AVG.tif') ) '_' profile_method '_cutoff_' norm_type '_' num2str(cutoff*100) '_stddev_ref_plot.png' ] ) );
% pause;

%%
figure(11);
for i=1:length(norm_stim_cell_reflectance) % Plot raw
% 
    plot(stim_cell_times{i}, norm_stim_cell_reflectance{i},'r' ); hold on;
%     plot(control_cell_times{i}, control_cell_reflectance{i},'b' ); hold on;
%     plot([0 length(cell_times{i})], [1+2*pstddev 1+2*pstddev],'r');
%     plot([0 length(cell_times{i})], [1-2*pstddev 1-2*pstddev],'r');
%     plot(stim_locs, 2*ones(size(stim_locs)),'r*'); hold off;
%     pause;
end
for i=1:length(norm_control_cell_reflectance) % Plot raw
    
    plot(control_cell_times{i}, norm_control_cell_reflectance{i},'b' ); hold on;
%     plot([0 length(cell_times{i})], [1+2*pstddev 1+2*pstddev],'r');
%     plot([0 length(cell_times{i})], [1-2*pstddev 1-2*pstddev],'r');
%     plot(stim_locs, 2*ones(size(stim_locs)),'r*'); hold off;
%     pause;
end
saveas(gcf, fullfile(mov_path, [ref_image_fname(1:end - length('_AVG.tif') ) '_' profile_method  '_cutoff_' norm_type '_' num2str(cutoff*100) '_raw_plot.png' ] ) );


% plot([0 length(cell_times{i})], [1+2*pstddev 1+2*pstddev],'r');
%     plot([0 length(cell_times{i})], [1-2*pstddev 1-2*pstddev],'r');
%     plot(stim_locs, 2*ones(size(stim_locs)),'r*'); hold off;
% xlabel('Time (s)'); ylabel('Normalized reflectance (1st-frame)');
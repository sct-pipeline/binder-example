#!/bin/bash
#
# Download, convert and process data.
#
# Usage:
#   ./batch_processing.sh
# 
# Dependencies:
# - dcm2niix (v1.0.20170130)
# - SCT (v4.0.0-beta.0)
#
# Author: Julien Cohen-Adad

# Exit if user presses CTRL+C (Linux) or CMD+C (OSX)
trap "echo Caught Keyboard Interrupt within script. Exiting now.; exit" INT

# Download example data
sct_download_data -d sct_example_data

# Go to MT folder
cd sct_example_data/mt/

# Segment spinal cord
sct_deepseg_sc -i t1w.nii.gz -c t1

# Create mask
sct_create_mask -i t1w.nii.gz -p centerline,t1w_seg.nii.gz -size 35mm -o t1w_mask.nii.gz

# Crop data for faster processing
sct_crop_image -i t1w.nii.gz -m t1w_mask.nii.gz -o t1w_crop.nii.gz

# Register PD->T1w
# Tips: here we only use rigid transformation because both images have very similar sequence parameters. We don't want to use SyN/BSplineSyN to avoid introducing spurious deformations.
sct_register_multimodal -i mt0.nii.gz -d t1w_crop.nii.gz -param step=1,type=im,algo=rigid,slicewise=1,metric=CC -x spline

# Register MT->T1w
sct_register_multimodal -i mt1.nii.gz -d t1w_crop.nii.gz -param step=1,type=im,algo=rigid,slicewise=1,metric=CC -x spline

# Create label 4 at the mid-FOV, because we know the FOV is centered at C3-C4 disc.
sct_label_utils -i t1w_seg.nii.gz -create-seg -1,4 -o label_c3c4.nii.gz

# Register template->T1w_ax (using template-T1w as initial transformation)
sct_register_to_template -i t1w_crop.nii.gz -s t1w_seg.nii.gz -ldisc label_c3c4.nii.gz -ref subject -c t1 -param step=1,type=seg,algo=slicereg,metric=MeanSquares,smooth=2:step=2,type=im,algo=bsplinesyn,metric=MeanSquares,iter=5,gradStep=0.5

# Warp template
sct_warp_template -d t1w_crop.nii.gz -w warp_template2anat.nii.gz

# Compute MTR
sct_compute_mtr -mt1 mt1_reg.nii.gz -mt0 mt0_reg.nii.gz

# Compute MTsat and T1
sct_compute_mtsat -mt mt1_reg.nii.gz -pd mt0_reg.nii.gz -t1 t1w_crop.nii.gz -trmt 57 -trpd 57 -trt1 15 -famt 9 -fapd 9 -fat1 15

# Extract MTR, MTsat and T1 in WM between C2 and C4 vertebral levels
sct_extract_metric -i mtr.nii.gz -l 51 -vert 2:4 -o results.csv
sct_extract_metric -i mtsat.nii.gz -l 51 -vert 2:4 -o results.csv -append 1
sct_extract_metric -i t1map.nii.gz -l 51 -vert 2:4 -o results.csv -append 1

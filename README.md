# antsCtLungRegistrationWithTotalSegmentator

Register inspiration and expiration lung CT using lung segmentations from TotalSegmentator

Based on [this](https://github.com/ntustison/antsCtLungRegistrationExample) example

# Instructions
* Download and install [ANTs](https://github.com/stnava/ANTs).
* Add the ANTs binary directory to your path environment variable.
* Install [TotalSegmentator] (https://github.com/wasserth/TotalSegmentator)

# Running the script
SegmentAndRegisterInspirationExpiration.sh -i inspiration_ct.nii.gz -e expiration_ct.nii.gz -o output_prefix 

options:
* -h show help
* -f use --fast in TotalSegmentator
* -r VALUE resolution (mm) to use for isotropic resampling on inputs (default=2)

# What the scripts does
1. Preprocessing
    1. Resample - Resample both inputs to an isotropic resolution (defualt = 2mm)
    2. Rescale - Rescale intensities in both inputs as registration metrics have problems with negative values
    3. Truncate - Remove "outlier" intensity value
    4. Denoise - Run inputs throught a denoising filter
2. Segmentation
    1. Segment lung lobes (both inputs) using TotalSegmentator
    2. Resample - put lung lobe values into resampled resolution
    3. Merge lobes into "whole lung" masks
    4. Segment lung vessels (both inputs) using TotalSegmentator
3. Registration
    1. Align left lung (expiration -> inspiration)
        1. Create lung region mask - dilate segmentation mask
        2. Run antsRegistration
        3. Mask out diplacments - limit field to lung 
    2. Align right lung
        1. Create lung region mask - dilate segmentation mask
        2. Run antsRegistration
        3. Mask out diplacments - limit field to lung 
    3. Merge displacement fields from 3.1 and 3.2
4. Postprocessing
    1. Smooth displacement field
    2. Smooth inverse displacement field
    3. Calculate Log Jacobian map for smoothed displacement field
5. Statistics
    1. WIP - currently deciding on what metrics to include
6. Cleanup
    1. Remove intermediate files     

    
    




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





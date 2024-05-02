#!/bin/sh
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=4
#module load ANTs

t1=`date +%s`

usage() { echo "Usage: $0 -i inspiration_ct -e expiration_ct -o output_prefix"; exit 1; }

inspiration=""
expiration=""
outname=""
res="2"
ts_fast=""

while getopts e:fi:o:hr: flag
do
  case "${flag}" in
     e) expiration=${OPTARG};;
     f) ts_fast="--fast";;
     i) inspiration=${OPTARG};;
     o) outname=${OPTARG};;
     h) usage;;
     r) res=${OPTARG};;
  esac
done

echo "Inspiration: $inspiration"
echo "Expiration: $expiration"

outputDirectory=`dirname $outname`
if [ ! -e "$outputDirectory" ]; then
  mkdir -p $outputDirectory
fi

inspiration_rs="${outname}inspiration_resampled.nii.gz"
expiration_rs="${outname}_xpiration_resampled.nii.gz"

inspirationPre="${outname}inspiration_preprocessed.nii.gz"
expirationPre="${outname}expiration_preprocessed.nii.gz"

echo "1 Preprocessing: Start."
if [[ ! -f "${inspirationPre}" ]] || [[ ! -f "${expirationPre}" ]]; then

  echo "1.1 Preprocessing: Resample CT images."

  ResampleImageBySpacing 3 ${inspiration} ${inspiration_rs} ${res} ${res} ${res}
  ResampleImageBySpacing 3 ${expiration} ${expiration_rs} ${res} ${res} ${res}

  echo "1.2 Preprocessing: Rescale intensities."

  ImageMath 3 $inspirationPre RescaleImage $inspiration_rs 0 1
  ImageMath 3 $expirationPre RescaleImage $expiration_rs 0 1

  echo "1.3 Preprocessing: Truncate image intensities."

  ImageMath 3 $inspirationPre TruncateImageIntensity $inspirationPre
  ImageMath 3 $expirationPre TruncateImageIntensity $expirationPre

  echo "1.4 Preprocessing: Denoise."

  DenoiseImage -d 3 -v 1 -i $inspirationPre -o $inspirationPre
  DenoiseImage -d 3 -v 1 -i $expirationPre -o $expirationPre
  
fi
echo "1 Preprocessing: Complete."

inspirationLobes="${outname}inspiration_lobemask.nii.gz"
expirationLobes="${outname}_xpiration_lobemask.nii.gz"

inspirationLungVesselsDir="${outname}inspiration_lungvessels"
expirationLungVesselsDir="${outname}expiration_lungvessels"

inspirationLungVessels="${outname}inspiration_lungvessels_resampled.nii.gz"
expirationLungVessels="${outname}expiration_lungvessels_resampled.nii.gz"

inspirationLobesRs="${outname}inspiration_lobemask_resampled.nii.gz"
expirationLobesRs="${outname}expiration_lobemask_resampled.nii.gz"

inspirationMask="${outname}inspiration_lungmask_resampled.nii.gz"
expirationMask="${outname}expiration_lungmask_resampled.nii.gz"

inspirationBinMask="${outname}inspiration_binmask_resampled.nii.gz"
expirationBinMask="${outname}expiration_binmask_resampled.nii.gz"


echo "2 Segmentation: Start."
if [[ ! -f "${inspirationMask}" ]] || [[ ! -f "${expirationMask}" ]]; then

  echo "2.1 Segmentation: Segmenting lungs lobes."

  # Run on full res and downsample
  TotalSegmentator -i $inspiration $ts_fast -ml -o ${inspirationLobes} --roi_subset lung_upper_lobe_left lung_lower_lobe_left lung_upper_lobe_right lung_middle_lobe_right lung_lower_lobe_right
  TotalSegmentator -i $expiration $ts_fast -ml -o ${expirationLobes} --roi_subset lung_upper_lobe_left lung_lower_lobe_left lung_upper_lobe_right lung_middle_lobe_right lung_lower_lobe_right

  echo "2.2 Segmentation: Resampling lung masks."

  # Resample lobe labels
  antsApplyTransforms -d 3 -v 1 -i ${inspirationLobes} -r ${inspiration_rs} -o ${inspirationLobesRs} -n GenericLabel 
  antsApplyTransforms -d 3 -v 1 -i ${expirationLobes} -r ${expiration_rs} -o ${expirationLobesRs} -n GenericLabel

  echo "2.3 Segmentation: Merging lobes to create whole lung masks."

  # One label per lung (left=1, right=2)
  ImageMath 3 ${inspirationMask} ReplaceVoxelValue ${inspirationLobesRs} 1 9 0
  ImageMath 3 ${inspirationMask} ReplaceVoxelValue ${inspirationMask} 10 11 1
  ImageMath 3 ${inspirationMask} ReplaceVoxelValue ${inspirationMask} 12 14 2
  ImageMath 3 ${inspirationMask} ReplaceVoxelValue ${inspirationMask} 15 1000 0
  ImageMath 3 ${expirationMask} ReplaceVoxelValue ${expirationLobesRs} 1 9 0
  ImageMath 3 ${expirationMask} ReplaceVoxelValue ${expirationMask} 10 11 1
  ImageMath 3 ${expirationMask} ReplaceVoxelValue ${expirationMask} 12 14 2
  ImageMath 3 ${expirationMask} ReplaceVoxelValue ${expirationMask} 15 1000 0

  echo "2.4 Segmentation: Segmenting lung vessels."

  # --fast does not with for this subtask
  TotalSegmentator -i $inspiration -o ${inspirationLungVesselsDir} -ta lung_vessels
  TotalSegmentator -i $expiration -o ${expirationLungVesselsDir} -ta lung_vessels

  # Mask of both lungs as label==1 for masking vessels
  ThresholdImage 3 ${inspirationMask} ${inspirationBinMask} 1 2 1 0 
  ThresholdImage 3 ${expirationMask} ${expirationBinMask} 1 2 1 0 

  # Mask lung vessels to only be in lung volumes
  ImageMath 3 ${inspirationLungVessels} m ${inspirationLungVesselsDir}/lung_vessels.nii.gz ${inspirationBinMask}
  ImageMath 3 ${expirationLungVessels} m ${expirationLungVesselsDir}/lung_vessels.nii.gz ${expirationBinMask}

fi
echo "2 Segmentation: Complete."

##############
#
# Perform registration one lung at a time
#  * we don't perform any linear registration.  There really isn't a linear
#    transform between inspiratory and expiratory scans since the global
#    position of the body basically remains the same.  In the case below,
#    we use a coarse B-spline registration on the the downsampled image
#    which should account for those large inspiration/expiration differences.
#  * the meaning of each option is given in the antsRegistration help
#    i.e., 'antsRegistration --help 1'
#  * '1' and '2' are the labels of the left and right lungs, respectively
#

echo "3 Registration: Start."
if [[ ! -f "${outname}0Warp.nii.gz" ]] || [[ ! -f "${outname}0InverseWarp.nii.gz" ]]; then

  for i in 1 2;
    do

      echo "3.${i} Registration: Start"

      tmpInspirationLung="${outputDirectory}/tmpInspirationLung.nii.gz"
      tmpExpirationLung="${outputDirectory}/tmpExpirationLung.nii.gz"
      tmpInspirationLungMask="${outputDirectory}/tmpInspirationLungMask.nii.gz"
      tmpExpirationLungMask="${outputDirectory}/tmpExpirationLungMask.nii.gz"

      echo "3.${i}.1 Registration: Create lung mask"

      ThresholdImage 3 $inspirationMask $tmpInspirationLungMask $i $i 1 0
      ThresholdImage 3 $expirationMask $tmpExpirationLungMask $i $i 1 0

      ImageMath 3 $tmpInspirationLungMask MD $tmpInspirationLungMask 10
      ImageMath 3 $tmpExpirationLungMask MD $tmpExpirationLungMask 10

      ImageMath 3 $tmpInspirationLung m $tmpInspirationLungMask $inspirationPre
      ImageMath 3 $tmpExpirationLung m $tmpExpirationLungMask $expirationPre

      warpFieldPrefix=${outname}Lung${i}

      echo "3.${i}.2 Registration: Align expiration to inspiration"

      antsRegistration -d 3 \
                      -v 1 \
                      -t BSplineSyN[0.1,80,0,3] \
                      -m MSQ[${tmpInspirationLung},${tmpExpirationLung},1,1] \
                      -c 100x100x100x50x0 \
                      -f 8x6x4x2x1 \
                      -s 2x1x0x0x0 \
                      -o ${warpFieldPrefix}

      echo "3.${i}.3 Registration: Limit displacements to lung region"
      # split the warps into components and mask out displacement field outside lung

      ThresholdImage 3 $inspirationMask $tmpInspirationLungMask $i $i 1 0
      ThresholdImage 3 $expirationMask $tmpExpirationLungMask $i $i 1 0

      ConvertImage 3 ${warpFieldPrefix}0Warp.nii.gz ${warpFieldPrefix}0Warp 10
      ConvertImage 3 ${warpFieldPrefix}0InverseWarp.nii.gz ${warpFieldPrefix}0InverseWarp 10

      for j in xvec yvec zvec;
        do
          ImageMath 3 ${warpFieldPrefix}0Warp${j}.nii.gz m ${warpFieldPrefix}0Warp${j}.nii.gz $tmpInspirationLungMask
          ImageMath 3 ${warpFieldPrefix}0InverseWarp${j}.nii.gz m ${warpFieldPrefix}0InverseWarp${j}.nii.gz $tmpExpirationLungMask
        done

      ConvertImage 3 ${warpFieldPrefix}0Warp ${warpFieldPrefix}0Warp.nii.gz 9
      ConvertImage 3 ${warpFieldPrefix}0InverseWarp ${warpFieldPrefix}0InverseWarp.nii.gz 9

      rm -f $tmpInspirationLung
      rm -f $tmpExpirationLung
      rm -f $tmpInspirationLungMask
      rm -f $tmpExpirationLungMask
      rm -f ${warpFieldPrefix}0Warpxvec.nii.gz
      rm -f ${warpFieldPrefix}0Warpyvec.nii.gz
      rm -f ${warpFieldPrefix}0Warpzvec.nii.gz

    done

  ## Combine the two warp fields

  echo "3.3 Registration: Merge displacement fields"
  antsApplyTransforms -d 3 -v 1 \
                      -o [${outname}0Warp.nii.gz,1] \
                      -r $inspirationPre \
                      -t ${outname}Lung10Warp.nii.gz \
                      -t ${outname}Lung20Warp.nii.gz

  echo "3.4 Registration: Merge inverese displacement fields"
  antsApplyTransforms -d 3 -v 1 \
                      -o [${outname}0InverseWarp.nii.gz,1] \
                      -r $expirationPre \
                      -t ${outname}Lung10InverseWarp.nii.gz \
                      -t ${outname}Lung20InverseWarp.nii.gz

fi
echo "3 Registration: Complete"

## Fit displacement field/s, if desired
echo "4 Postprocessing: Start."
if [[ ! -f "${outname}Smooth0Warp.nii.gz" ]] || [[ ! -f "${outname}Smooth0InverseWarp.nii.gz" ]]; then

  tmpInspirationLungMask="${outputDirectory}/tmpInspirationLungMask.nii.gz"
  tmpExpirationLungMask="${outputDirectory}/tmpExpirationLungMask.nii.gz"

  ThresholdImage 3 $inspirationMask $tmpInspirationLungMask 0 0 0 1
  ThresholdImage 3 $expirationMask $tmpExpirationLungMask 0 0 0 1

  echo "4.1 Postprocessing: Smooth displacement field."

  SmoothDisplacementField 3 ${outname}0Warp.nii.gz \
                            ${outname}Smooth0Warp.nii.gz \
                            4x4x4 8 3 0 \
                            $tmpInspirationLungMask

  echo "4.2 Postprocessing: Smooth inverse displacement field."

  SmoothDisplacementField 3 ${outname}0InverseWarp.nii.gz \
                            ${outname}Smooth0InverseWarp.nii.gz \
                            4x4x4 8 3 0 \
                            $tmpExpirationLungMask
fi

# Calculate Jacobian from displacement field 
if [[ ! -f "${outname}smooth_log_jabocian_inspiration.nii.gz" ]]; then

  echo "4.3 Postprocessing: Create LogJacobian map."
  CreateJacobianDeterminantImage 3 ${outname}Smooth0Warp.nii.gz ${outname}smooth_log_jabocian_inspiration.nii.gz 1 1
  CreateJacobianDeterminantImage 3 ${outname}Smooth0InverseWarp.nii.gz ${outname}smooth_log_jacobian_expiration.nii.gz 1 1

fi
echo "4 Postprocessing: Complete."

echo "5 Statistics and Metrics. Start."
echo "5 Statistics and Metrics. WIP"
echo "5 Statistics and Metrics. Complete."

echo "6 Cleanup: Start"

rm -f $tmpInspirationLungMask
rm -f $tmpExpirationLungMask
rm -f ${outname}Lung*Warp.nii.gz
#rm -f ${inspirationPre} 
#rm -f ${expirationPre}

echo "6 Cleanup: Complete."

t2=`date +%s`
tm=$(( $t2 - $t1 ))
echo "Run time: $tm seconds"

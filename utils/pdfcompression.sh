#!/bin/bash

# Purpose: Compress a PDF file using Ghostscript with balanced quality and size reduction.
# This script uses specific settings to reduce the file size by approximately 2/3 while maintaining readability.
# Input file: "/home/xander/Downloads/DelResFeb2025-compressed.pdf" - The original PDF to be compressed.
# Output file: "/home/xander/Downloads/DelResume2.pdf" - The compressed PDF result.

# Run Ghostscript with the following options:
gs \
  -sDEVICE=pdfwrite \
    # Set the output device to 'pdfwrite', which generates a new PDF file. \
  -dCompatibilityLevel=1.4 \
    # Set PDF compatibility level to 1.4, ensuring broad compatibility with PDF viewers. \
  -dPDFSETTINGS=/ebook \
    # Use the 'ebook' preset, balancing quality and size for eBook viewing (moderate compression). \
  -dColorImageDownsampleType=/Bicubic \
    # Use Bicubic downsampling for color images, providing better quality than simpler methods. \
  -dColorImageResolution=150 \
    # Set color image resolution to 150 DPI, reducing size while maintaining reasonable quality. \
  -dGrayImageDownsampleType=/Bicubic \
    # Use Bicubic downsampling for grayscale images, ensuring smooth quality reduction. \
  -dGrayImageResolution=150 \
    # Set grayscale image resolution to 150 DPI, balancing size and readability. \
  -dMonoImageDownsampleType=/Subsample \
    # Use Subsample downsampling for monochrome images, which is faster but less smooth. \
  -dMonoImageResolution=300 \
    # Set monochrome image resolution to 300 DPI, preserving detail for line art and text. \
  -dDownsampleColorImages=true \
    # Enable downsampling for color images if they exceed the specified resolution. \
  -dDownsampleGrayImages=true \
    # Enable downsampling for grayscale images if they exceed the specified resolution. \
  -dDownsampleMonoImages=true \
    # Enable downsampling for monochrome images if they exceed the specified resolution. \
  -dColorImageDownsampleThreshold=1.5 \
    # Set threshold for color image downsampling (1.5x resolution), controlling when downsampling occurs. \
  -dGrayImageDownsampleThreshold=1.5 \
    # Set threshold for grayscale image downsampling (1.5x resolution), controlling when downsampling occurs. \
  -dMonoImageDownsampleThreshold=1.5 \
    # Set threshold for monochrome image downsampling (1.5x resolution), controlling when downsampling occurs. \
  -dCompressFonts=true \
    # Enable font compression to reduce file size by compressing embedded fonts. \
  -dDetectDuplicateImages=true \
    # Detect and remove duplicate images, storing only one copy to save space. \
  -dCompressImages=true \
    # Enable image compression to reduce the size of embedded images. \
  -dAutoFilterColorImages=false \
    # Disable automatic filter selection for color images, using manual settings instead. \
  -dAutoFilterGrayImages=false \
    # Disable automatic filter selection for grayscale images, using manual settings instead. \
  -dColorImageFilter=/DCTEncode \
    # Use JPEG compression (DCTEncode) for color images, balancing quality and size. \
  -dGrayImageFilter=/DCTEncode \
    # Use JPEG compression (DCTEncode) for grayscale images, balancing quality and size. \
  -dBATCH \
    # Run in batch mode, exiting after processing without entering interactive mode. \
  -dNOPAUSE \
    # Disable pausing between pages, ensuring continuous processing without user input. \
  -sOutputFile="/home/usr/Downloads/pdfName.pdf" \
    # Specify the output file path; where the compressed PDF will be saved. \
  "/home/usr/Downloads/pdfName.pdf"
    # Specify the input file path; the original PDF to compress.

    #gs -sDEVICE=pdfwrite    -dCompatibilityLevel=1.4    -dPDFSETTINGS=/ebook    -dColorImageDownsampleType=/Bicubic    -dColorImageResolution=150    -dGrayImageDownsampleType=/Bicubic    -dGrayImageResolution=150    -dMonoImageDownsampleType=/Subsample    -dMonoImageResolution=300    -dDownsampleColorImages=true    -dDownsampleGrayImages=true    -dDownsampleMonoImages=true    -dColorImageDownsampleThreshold=1.5    -dGrayImageDownsampleThreshold=1.5    -dMonoImageDownsampleThreshold=1.5    -dCompressFonts=true    -dDetectDuplicateImages=true    -dCompressImages=true    -dAutoFilterColorImages=false    -dAutoFilterGrayImages=false    -dColorImageFilter=/DCTEncode    -dGrayImageFilter=/DCTEncode    -dBATCH    -dNOPAUSE    -sOutputFile="/home/xander/Downloads/DelResume2.pdf"    "/home/xander/Downloads/DelResFeb2025-compressed.pdf"
#

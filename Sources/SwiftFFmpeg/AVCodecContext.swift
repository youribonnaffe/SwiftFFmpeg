//
//  AVCodecContext.swift
//  SwiftFFmpeg
//
//  Created by sunlubo on 2018/6/29.
//

import CFFmpeg

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
  import Darwin
#else
  import Glibc
#endif

public typealias AVGetFormatHandler = (AVCodecContext, [AVPixelFormat]) -> AVPixelFormat

typealias CodecContextBoxValue = (
  opaque: UnsafeMutableRawPointer?,
  getFormat: AVGetFormatHandler?
)
typealias CodecContextBox = Box<CodecContextBoxValue>

// MARK: - AVCodecContext

typealias CAVCodecContext = CFFmpeg.AVCodecContext

public final class AVCodecContext {
  let cContextPtr: UnsafeMutablePointer<CAVCodecContext>
  var cContext: CAVCodecContext { cContextPtr.pointee }

  fileprivate var opaqueBox: CodecContextBox? {
    didSet {
      if let box = opaqueBox {
        cContextPtr.pointee.opaque = Unmanaged.passUnretained(box).toOpaque()
      } else {
        cContextPtr.pointee.opaque = nil
      }
    }
  }
  private var freeWhenDone: Bool = false

  init(cContextPtr: UnsafeMutablePointer<CAVCodecContext>) {
    self.cContextPtr = cContextPtr
  }

  /// Creates an `AVCodecContext` and set its fields to default values.
  ///
  /// - Parameter codec: codec
  public init(codec: AVCodec? = nil) {
    guard let ctxPtr = avcodec_alloc_context3(codec?.cCodecPtr) else {
      abort("avcodec_alloc_context3")
    }
    self.cContextPtr = ctxPtr
    self.freeWhenDone = true
  }

  deinit {
    if freeWhenDone {
      var ps: UnsafeMutablePointer<CAVCodecContext>? = cContextPtr
      avcodec_free_context(&ps)
    }
  }

  /// The codec's media type.
  public var mediaType: AVMediaType {
    cContext.codec_type
  }

  public var codec: AVCodec? {
    get {
      if let ptr = cContext.codec {
        return AVCodec(cCodecPtr: ptr.mutable)
      }
      return nil
    }
    set { cContextPtr.pointee.codec = UnsafePointer(newValue?.cCodecPtr) }
  }

  /// The codec's id.
  public var codecId: AVCodecID {
    get { cContext.codec_id }
    set { cContextPtr.pointee.codec_id = newValue }
  }

  /// fourcc (LSB first, so "ABCD" -> ('D'<<24) + ('C'<<16) + ('B'<<8) + 'A').
  ///
  /// This is used to work around some encoder bugs.
  /// A demuxer should set this to what is stored in the field used to identify the codec.
  /// If there are multiple such fields in a container then the demuxer should choose the one
  /// which maximizes the information about the used codec.
  /// If the codec tag field in a container is larger than 32 bits then the demuxer should
  /// remap the longer ID to 32 bits with a table or other structure. Alternatively a new
  /// extra_codec_tag + size could be added but for this a clear advantage must be demonstrated
  /// first.
  ///
  /// - encoding: Set by user, if not then the default based on `codecId` will be used.
  /// - decoding: Set by user, will be converted to uppercase by libavcodec during init.
  public var codecTag: UInt32 {
    get { cContext.codec_tag }
    set { cContextPtr.pointee.codec_tag = newValue }
  }

  /// Private data of the user, can be used to carry app specific stuff.
  ///
  /// - encoding: Set by user.
  /// - decoding: Set by user.
  public var opaque: UnsafeMutableRawPointer? {
    get { opaqueBox?.value.opaque }
    set { opaqueBox = CodecContextBox((opaque: newValue, getFormat: opaqueBox?.value.getFormat)) }
  }

  /// The average bitrate.
  ///
  /// - encoding: Set by user, unused for constant quantizer encoding.
  /// - decoding: Set by user, may be overwritten by libavcodec if this info is available in the stream.
  public var bitRate: Int64 {
    get { cContext.bit_rate }
    set { cContextPtr.pointee.bit_rate = newValue }
  }

  /// Number of bits the bitstream is allowed to diverge from the reference.
  /// The reference can be CBR (for CBR pass1) or VBR (for pass2).
  ///
  /// - encoding: Set by user, unused for constant quantizer encoding.
  /// - decoding: Unused.
  public var bitRateTolerance: Int {
    get { Int(cContext.bit_rate_tolerance) }
    set { cContextPtr.pointee.bit_rate_tolerance = Int32(newValue) }
  }

  /// `AVCodecContext.Flag`
  ///
  /// - encoding: Set by user.
  /// - decoding: Set by user.
  public var flags: Flag {
    get { Flag(rawValue: UInt32(cContext.flags)) }
    set { cContextPtr.pointee.flags = Int32(newValue.rawValue) }
  }

  /// `AVCodecContext.Flag2`
  ///
  /// - encoding: Set by user.
  /// - decoding: Set by user.
  public var flags2: Flag2 {
    get { Flag2(rawValue: cContext.flags2) }
    set { cContextPtr.pointee.flags2 = newValue.rawValue }
  }

  /// Some codecs need / can use extradata like Huffman tables.
  ///
  /// - MJPEG: Huffman tables
  /// - rv10: additional flags
  /// - MPEG-4: global headers (they can be in the bitstream or here)
  ///
  /// The allocated memory should be `AVConstant.inputBufferPaddingSize` bytes larger
  /// than `extradataSize` to avoid problems if it is read with the bitstream reader.
  /// The bytewise contents of extradata must not depend on the architecture or CPU endianness.
  /// Must be allocated with the `AVIO.malloc(size:)` family of functions.
  ///
  /// - encoding: Set/allocated/freed by libavcodec.
  /// - decoding: Set/allocated/freed by user.
  public var extradata: UnsafeMutablePointer<UInt8>? {
    get { cContext.extradata }
    set { cContextPtr.pointee.extradata = newValue }
  }

  /// The size of the extradata content in bytes.
  public var extradataSize: Int {
    get { Int(cContext.extradata_size) }
    set { cContextPtr.pointee.extradata_size = Int32(newValue) }
  }

  /// This is the fundamental unit of time (in seconds) in terms of which frame timestamps
  /// are represented. For fixed-fps content, timebase should be 1/framerate and timestamp
  /// increments should be identically 1.
  /// This often, but not always is the inverse of the frame rate or field rate for video.
  /// 1/timebase is not the average frame rate if the frame rate is not constant.
  ///
  /// Like containers, elementary streams also can store timestamps, 1/timebase
  /// is the unit in which these timestamps are specified.
  /// As example of such codec timebase see ISO/IEC 14496-2:2001(E)
  /// vop_time_increment_resolution and fixed_vop_rate
  /// (fixed_vop_rate == 0 implies that it is different from the framerate)
  ///
  /// - encoding: Must be set by user.
  /// - decoding: The use of this field for decoding is deprecated. Use framerate instead.
  public var timebase: AVRational {
    get { cContext.time_base }
    set { cContextPtr.pointee.time_base = newValue }
  }

  /// Frame counter.
  ///
  /// - encoding: Total number of frames passed to the encoder so far.
  /// - decoding: Total number of frames returned from the decoder so far.
  public var frameNumber: Int {
    Int(cContext.frame_number)
  }

  /// A reference to the `AVHWFramesContext` describing the input (for encoding)
  /// or output (decoding) frames. The reference is set by the caller and
  /// afterwards owned (and freed) by libavcodec - it should never be read by
  /// the caller after being set.
  ///
  /// - encoding: For hardware encoders configured to use a hwaccel pixel
  ///   format, this field should be set by the caller to a reference
  ///   to the `AVHWFramesContext` describing input frames.
  ///   `AVHWFramesContext.pixelFormat` must be equal to `AVCodecContext.pixelFormat`.
  ///
  ///   This field should be set before `openCodec(_:options:)` is called.
  ///
  /// - decoding: This field should be set by the caller from the `getFormat`
  ///   callback. The previous reference (if any) will always be
  ///   unreffed by libavcodec before the `getFormat` call.
  ///
  ///   If the default `get_buffer2()` is used with a hwaccel pixel format,
  ///   then this `AVHWFramesContext` will be used for allocating the frame buffers.
  public var hwFramesContext: AVHWFramesContext? {
    get {
      if let ctxPtr = cContext.hw_frames_ctx {
        return AVHWFramesContext(cBufferPtr: ctxPtr)
      }
      return nil
    }
    set { cContextPtr.pointee.hw_frames_ctx = av_buffer_ref(newValue?.cBufferPtr) }
  }

  /// A reference to the `AVHWDeviceContext` describing the device which will
  /// be used by a hardware encoder/decoder. The reference is set by the caller
  /// and afterwards owned (and freed) by libavcodec.
  ///
  /// This should be used if either the codec device does not require
  /// hardware frames or any that are used are to be allocated internally by
  /// libavcodec. If the user wishes to supply any of the frames used as
  /// encoder input or decoder output then `hwFramesContext` should be used
  /// instead. When `hwFramesContext` is set in `getFormat` for a decoder, this
  /// field will be ignored while decoding the associated stream segment, but
  /// may again be used on a following one after another `getFormat` call.
  ///
  /// For both encoders and decoders this field should be set before
  /// `openCodec(_:options:)` is called and must not be written to thereafter.
  ///
  /// Note that some decoders may require this field to be set initially in
  /// order to support `hwFramesContext` at all - in that case, all frames
  /// contexts used must be created on the same device.
  public var hwDeviceContext: AVHWDeviceContext? {
    get {
      if let ctxPtr = cContext.hw_device_ctx {
        return AVHWDeviceContext(cBufferPtr: ctxPtr)
      }
      return nil
    }
    set { cContextPtr.pointee.hw_device_ctx = av_buffer_ref(newValue?.cBufferPtr) }
  }

  /// A Boolean value indicating whether the codec is open.
  public var isOpen: Bool {
    avcodec_is_open(cContextPtr) > 0
  }

  /// Fill the codec context based on the values from the supplied codec parameters.
  ///
  /// - Parameter params: codec parameters
  public func setParameters(_ params: AVCodecParameters) {
    abortIfFail(avcodec_parameters_to_context(cContextPtr, params.cParametersPtr))
  }

  /// Initialize the `AVCodecContext`.
  ///
  /// - Parameters:
  ///   - codec: The codec to open this context for. If a non-NULL codec has been previously
  ///     passed to `init(codec:)` or for this context, then this parameter _MUST_ be either `nil`
  ///     or equal to the previously passed codec.
  ///   - options: A dictionary filled with `AVCodecContext` and codec-private options.
  /// - Throws: AVError
  public func openCodec(_ codec: AVCodec? = nil, options: [String: String]? = nil) throws {
    var pm: OpaquePointer? = options?.toAVDict()
    defer { av_dict_free(&pm) }

    try throwIfFail(avcodec_open2(cContextPtr, codec?.cCodecPtr ?? self.codec?.cCodecPtr, &pm))

    dumpUnrecognizedOptions(pm)
  }

  /// Supply raw packet data as input to a decoder.
  ///
  /// - Parameter packet: The input `AVPacket`. Usually, this will be a single video frame,
  ///   or several complete audio frames.
  ///   It can be `nil` (or an `AVPacket` with data set to `nil` and size set to 0);
  ///   in this case, it is considered a flush packet, which signals the end of the stream.
  ///   Sending the first flush packet will return success. Subsequent ones are unnecessary
  ///   and will throw `AVError.eof`. If the decoder still has frames buffered, it will
  ///   return them after sending a flush packet.
  /// - Throws:
  ///     - `AVError.tryAgain` if input is not accepted in the current state - user must read output
  ///       with `receiveFrame`. (once all output is read, the packet should be resent, and the call
  ///       will not fail with `AVError.tryAgain`).
  ///     - `AVError.eof` if the decoder has been flushed, and no new packets can be sent to it.
  ///       (also returned if more than 1 flush packet is sent)
  ///     - `AVError.invalidArgument` if codec not opened, it is an encoder, or requires flush
  ///     - `AVError.outOfMemory` if failed to add packet to internal queue, or similar.
  ///     - legitimate decoding errors
  public func sendPacket(_ packet: AVPacket?) throws {
    try throwIfFail(avcodec_send_packet(cContextPtr, packet?.cPacketPtr))
  }

  /// Return decoded output data from a decoder.
  ///
  /// - Parameter frame: This will be set to a reference-counted video or audio frame (depending on
  ///   the decoder type) allocated by the decoder.
  /// - Throws:
  ///     - `AVError.tryAgain` if output is not available in this state - user must try to send new input.
  ///     - `AVError.eof` if the decoder has been fully flushed, and there will be no more output frames.
  ///     - `AVError.invalidArgument` if codec not opened, or it is an encoder.
  ///     - legitimate decoding errors
  public func receiveFrame(_ frame: AVFrame) throws {
    try throwIfFail(avcodec_receive_frame(cContextPtr, frame.cFramePtr))
  }

  /// Supply a raw video or audio frame to the encoder.
  ///
  /// - Parameter frame: `AVFrame` containing the raw audio or video frame to be encoded.
  ///   It can be `nil`, in which case it is considered a flush packet. This signals the end of the stream.
  ///   If the encoder still has packets buffered, it will return them after this call.
  ///   Once flushing mode has been entered, additional flush packets are ignored, and sending frames
  ///   will return `AVError.eof`.
  /// - Throws:
  ///     - `AVError.tryAgain` if input is not accepted in the current state - user must read output
  ///       with `receivePacket`. (once all output is read, the packet should be resent, and the call
  ///       will not fail with `AVError.tryAgain`).
  ///     - `AVError.eof` if the encoder has been flushed, and no new frames can be sent to it.
  ///     - `AVError.invalidArgument` if codec not opened, refcounted_frames not set, it is a decoder,
  ///       or requires flush.
  ///     - `AVError.outOfMemory` if failed to add packet to internal queue, or similar.
  ///     - legitimate decoding errors
  public func sendFrame(_ frame: AVFrame?) throws {
    try throwIfFail(avcodec_send_frame(cContextPtr, frame?.cFramePtr))
  }

  /// Read encoded data from the encoder.
  ///
  /// - Parameter packet: This will be set to a reference-counted packet allocated by the encoder.
  /// - Throws:
  ///     - `AVError.tryAgain` if output is not available in the current state - user must try to send input.
  ///     - `AVError.eof` if the encoder has been fully flushed, and there will be no more output packets.
  ///     - `AVError.invalidArgument` if codec not opened, or it is an encoder.
  ///     - legitimate decoding errors
  public func receivePacket(_ packet: AVPacket) throws {
    try throwIfFail(avcodec_receive_packet(cContextPtr, packet.cPacketPtr))
  }

  /// Reset the internal decoder state / flush internal buffers. Should be called
  /// e.g. when seeking or when switching to a different stream.
  ///
  /// - Note: when refcounted frames are not used (i.e. avctx->refcounted_frames is 0),
  ///   this invalidates the frames previously returned from the decoder. When
  ///   refcounted frames are used, the decoder just releases any references it might
  ///   keep internally, but the caller's reference remains valid.
  public func flush() {
    avcodec_flush_buffers(cContextPtr)
  }
}

// MARK: - AVCodecContext.Flag

extension AVCodecContext {

  /// Encoding support
  ///
  /// These flags can be passed in `AVCodecContext.flags` before initialization.
  public struct Flag: OptionSet {
    /// Allow decoders to produce frames with data planes that are not aligned
    /// to CPU requirements (e.g. due to cropping).
    public static let unaligned = Flag(rawValue: UInt32(AV_CODEC_FLAG_UNALIGNED))
    /// Use fixed qscale.
    public static let qscale = Flag(rawValue: UInt32(AV_CODEC_FLAG_QSCALE))
    /// 4 MV per MB allowed / advanced prediction for H.263.
    public static let p4mv = Flag(rawValue: UInt32(AV_CODEC_FLAG_4MV))
    /// Output even those frames that might be corrupted.
    public static let outputCorrupted = Flag(rawValue: UInt32(AV_CODEC_FLAG_OUTPUT_CORRUPT))
    /// Use qpel MC.
    public static let qpel = Flag(rawValue: UInt32(AV_CODEC_FLAG_QPEL))
    /// Use internal 2pass ratecontrol in first pass mode.
    public static let pass1 = Flag(rawValue: UInt32(AV_CODEC_FLAG_PASS1))
    /// Use internal 2pass ratecontrol in second pass mode.
    public static let pass2 = Flag(rawValue: UInt32(AV_CODEC_FLAG_PASS2))
    /// loop filter.
    public static let loopFilter = Flag(rawValue: UInt32(AV_CODEC_FLAG_LOOP_FILTER))
    /// Only decode/encode grayscale.
    public static let gray = Flag(rawValue: UInt32(AV_CODEC_FLAG_GRAY))
    /// error[?] variables will be set during encoding.
    public static let psnr = Flag(rawValue: UInt32(AV_CODEC_FLAG_PSNR))
    /// Input bitstream might be truncated at a random location instead of only at frame boundaries.
    public static let truncated = Flag(rawValue: UInt32(AV_CODEC_FLAG_TRUNCATED))
    /// Use interlaced DCT.
    public static let interlacedDCT = Flag(rawValue: UInt32(AV_CODEC_FLAG_INTERLACED_DCT))
    /// Force low delay.
    public static let lowDelay = Flag(rawValue: UInt32(AV_CODEC_FLAG_LOW_DELAY))
    /// Place global headers in extradata instead of every keyframe.
    public static let globalHeader = Flag(rawValue: UInt32(AV_CODEC_FLAG_GLOBAL_HEADER))
    /// Use only bitexact stuff (except (I)DCT).
    public static let bitexact = Flag(rawValue: UInt32(AV_CODEC_FLAG_BITEXACT))
    /// H.263 advanced intra coding / MPEG-4 AC prediction
    public static let acPred = Flag(rawValue: UInt32(AV_CODEC_FLAG_AC_PRED))
    /// interlaced motion estimation
    public static let interlacedME = Flag(rawValue: UInt32(AV_CODEC_FLAG_INTERLACED_ME))
    public static let closedGOP = Flag(rawValue: AV_CODEC_FLAG_CLOSED_GOP)

    public let rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }
  }
}

extension AVCodecContext.Flag: CustomStringConvertible {

  public var description: String {
    var str = "["
    if contains(.unaligned) { str += "unaligned, " }
    if contains(.qscale) { str += "qscale, " }
    if contains(.p4mv) { str += "p4mv, " }
    if contains(.outputCorrupted) { str += "outputCorrupted, " }
    if contains(.qpel) { str += "qpel, " }
    if contains(.pass1) { str += "pass1, " }
    if contains(.pass2) { str += "pass2, " }
    if contains(.loopFilter) { str += "loopFilter, " }
    if contains(.gray) { str += "gray, " }
    if contains(.psnr) { str += "psnr, " }
    if contains(.truncated) { str += "truncated, " }
    if contains(.interlacedDCT) { str += "interlacedDCT, " }
    if contains(.lowDelay) { str += "lowDelay, " }
    if contains(.globalHeader) { str += "globalHeader, " }
    if contains(.bitexact) { str += "bitexact, " }
    if contains(.acPred) { str += "acPred, " }
    if contains(.interlacedME) { str += "interlacedME, " }
    if contains(.closedGOP) { str += "closedGOP, " }
    if str.suffix(2) == ", " {
      str.removeLast(2)
    }
    str += "]"
    return str
  }
}

// MARK: - AVCodecContext.Flag2

extension AVCodecContext {

  /// Encoding support
  ///
  /// These flags can be passed in `AVCodecContext.flags2` before initialization.
  public struct Flag2: OptionSet {
    /// Allow non spec compliant speedup tricks.
    public static let fast = Flag2(rawValue: AV_CODEC_FLAG2_FAST)
    /// Skip bitstream encoding.
    public static let noOutput = Flag2(rawValue: AV_CODEC_FLAG2_NO_OUTPUT)
    /// Place global headers at every keyframe instead of in extradata.
    public static let localHeader = Flag2(rawValue: AV_CODEC_FLAG2_LOCAL_HEADER)
    /// Input bitstream might be truncated at a packet boundaries instead of only at frame boundaries.
    public static let chunks = Flag2(rawValue: AV_CODEC_FLAG2_CHUNKS)
    /// Discard cropping information from SPS.
    public static let ignoreCrop = Flag2(rawValue: AV_CODEC_FLAG2_IGNORE_CROP)
    /// Show all frames before the first keyframe.
    public static let showAll = Flag2(rawValue: AV_CODEC_FLAG2_SHOW_ALL)
    /// Export motion vectors through frame side data.
    public static let exportMVS = Flag2(rawValue: AV_CODEC_FLAG2_EXPORT_MVS)
    /// Do not skip samples and export skip information as frame side data.
    public static let skipManual = Flag2(rawValue: AV_CODEC_FLAG2_SKIP_MANUAL)
    /// Do not reset ASS ReadOrder field on flush (subtitles decoding).
    public static let roFlushNoop = Flag2(rawValue: AV_CODEC_FLAG2_RO_FLUSH_NOOP)

    public let rawValue: Int32

    public init(rawValue: Int32) { self.rawValue = rawValue }
  }
}

extension AVCodecContext.Flag2: CustomStringConvertible {

  public var description: String {
    var str = "["
    if contains(.fast) { str += "fast, " }
    if contains(.noOutput) { str += "noOutput, " }
    if contains(.localHeader) { str += "localHeader, " }
    if contains(.chunks) { str += "chunks, " }
    if contains(.ignoreCrop) { str += "ignoreCrop, " }
    if contains(.showAll) { str += "showAll, " }
    if contains(.exportMVS) { str += "exportMVS, " }
    if contains(.skipManual) { str += "skipManual, " }
    if contains(.roFlushNoop) { str += "roFlushNoop, " }
    if str.suffix(2) == ", " {
      str.removeLast(2)
    }
    str += "]"
    return str
  }
}

// MARK: - Video

extension AVCodecContext {

  /// The width of the picture.
  ///
  /// - encoding: Must be set by user.
  /// - decoding: May be set by the user before opening the decoder if known e.g. from the container.
  ///   Some decoders will require the dimensions to be set by the caller. During decoding, the decoder may
  ///   overwrite those values as required while parsing the data.
  public var width: Int {
    get { Int(cContext.width) }
    set { cContextPtr.pointee.width = Int32(newValue) }
  }

  /// The height of the picture.
  ///
  /// - encoding: Must be set by user.
  /// - decoding: May be set by the user before opening the decoder if known e.g. from the container.
  ///   Some decoders will require the dimensions to be set by the caller. During decoding, the decoder may
  ///   overwrite those values as required while parsing the data.
  public var height: Int {
    get { Int(cContext.height) }
    set { cContextPtr.pointee.height = Int32(newValue) }
  }

  /// Bitstream width, may be different from `width` e.g. when the decoded frame is cropped before
  /// being output or lowres is enabled.
  ///
  /// - encoding: Unused.
  /// - decoding: May be set by the user before opening the decoder if known e.g. from the container.
  ///   During decoding, the decoder may overwrite those values as required while parsing the data.
  public var codedWidth: Int {
    get { Int(cContext.coded_width) }
    set { cContextPtr.pointee.coded_width = Int32(newValue) }
  }

  /// Bitstream height, may be different from `height` e.g. when the decoded frame is cropped before
  /// being output or lowres is enabled.
  ///
  /// - encoding: Unused.
  /// - decoding: May be set by the user before opening the decoder if known e.g. from the container.
  ///   During decoding, the decoder may overwrite those values as required while parsing the data.
  public var codedHeight: Int {
    get { Int(cContext.coded_height) }
    set { cContextPtr.pointee.coded_height = Int32(newValue) }
  }

  /// The number of pictures in a group of pictures, or 0 for intra_only.
  ///
  /// - encoding: Set by user.
  /// - decoding: Unused.
  public var gopSize: Int {
    get { Int(cContext.gop_size) }
    set { cContextPtr.pointee.gop_size = Int32(newValue) }
  }

  /// The pixel format of the picture.
  ///
  /// - encoding: Set by user.
  /// - decoding: Set by user if known, overridden by codec while parsing the data.
  public var pixelFormat: AVPixelFormat {
    get { cContext.pix_fmt }
    set { cContextPtr.pointee.pix_fmt = newValue }
  }

  /// The callback used to negotiate the pixel format.
  ///
  /// - Note: The callback may be called again immediately if initialization for
  ///   the selected (hardware-accelerated) pixel format failed.
  ///
  /// - Warning: Behavior is undefined if the callback returns a value not
  ///   in the fmt list of formats.
  ///
  /// - encoding: Unused.
  /// - decoding: Set by user, if not set the native format will be chosen.
  public var getFormat: AVGetFormatHandler? {
    get { opaqueBox?.value.getFormat }
    set {
      opaqueBox = CodecContextBox((opaque: opaqueBox?.value.opaque, getFormat: newValue))

      var handler:
        (
          @convention(c) (
            UnsafeMutablePointer<CAVCodecContext>?, UnsafePointer<AVPixelFormat>?
          ) -> AVPixelFormat
        )!
      if newValue != nil {
        handler = { ctx, fmts in
          let handler = Unmanaged<CodecContextBox>.fromOpaque(
            UnsafeRawPointer(ctx!.pointee.opaque!)
          )
          .takeUnretainedValue()
          .value
          .getFormat!
          let list = values(fmts, until: AVPixelFormat.none) ?? []
          return handler(AVCodecContext(cContextPtr: ctx!), list)
        }
      }
      cContextPtr.pointee.get_format = handler
    }
  }

  /// Maximum number of B-frames between non-B-frames.
  ///
  /// - Note: The output will be delayed by __max_b_frames+1__ relative to the input.
  ///
  /// - encoding: Set by user.
  /// - decoding: Unused.
  public var maxBFrames: Int {
    get { Int(cContext.max_b_frames) }
    set { cContextPtr.pointee.max_b_frames = Int32(newValue) }
  }

  /// Macroblock decision mode.
  ///
  /// - encoding: Set by user.
  /// - decoding: Unused.
  public var mbDecision: Int {
    get { Int(cContext.mb_decision) }
    set { cContextPtr.pointee.mb_decision = Int32(newValue) }
  }

  /// Sample aspect ratio (0/0 if unknown).
  ///
  /// That is the width of a pixel divided by the height of the pixel.
  /// Numerator and denominator must be relatively prime and smaller than 256 for some video standards.
  ///
  /// - encoding: Set by user.
  /// - decoding: Set by codec.
  public var sampleAspectRatio: AVRational {
    get { cContext.sample_aspect_ratio }
    set { cContextPtr.pointee.sample_aspect_ratio = newValue }
  }

  /// low resolution decoding, 1->1/2 size, 2->1/4 size
  ///
  /// - encoding: Unused.
  /// - decoding: Set by user.
  public var lowres: Int {
    Int(cContext.lowres)
  }

  /// The framerate of the video.
  ///
  /// - encoding: May be used to signal the framerate of CFR content to an encoder.
  /// - decoding: For codecs that store a framerate value in the compressed bitstream,
  ///   the decoder may export it here. 0/1 when unknown.
  public var framerate: AVRational {
    get { cContext.framerate }
    set { cContextPtr.pointee.framerate = newValue }
  }
}

// MARK: - Audio

extension AVCodecContext {

  /// Samples per second.
  public var sampleRate: Int {
    get { Int(cContext.sample_rate) }
    set { cContextPtr.pointee.sample_rate = Int32(newValue) }
  }

  /// Number of audio channels.
  public var channelCount: Int {
    get { Int(cContext.channels) }
    set { cContextPtr.pointee.channels = Int32(newValue) }
  }

  /// Audio sample format.
  ///
  /// - encoding: Set by user.
  /// - decoding: Set by libavcodec.
  public var sampleFormat: AVSampleFormat {
    get { cContext.sample_fmt }
    set { cContextPtr.pointee.sample_fmt = newValue }
  }

  /// Number of samples per channel in an audio frame.
  public var frameSize: Int {
    get { Int(cContext.frame_size) }
    set { cContextPtr.pointee.frame_size = Int32(newValue) }
  }

  /// Audio channel layout.
  ///
  /// - encoding: Set by user.
  /// - decoding: Set by user, may be overwritten by codec.
  public var channelLayout: AVChannelLayout {
    get { AVChannelLayout(rawValue: cContext.channel_layout) }
    set { cContextPtr.pointee.channel_layout = newValue.rawValue }
  }
}

// MARK: - Multithreading

extension AVCodecContext {

  /// Which multithreading methods to use.
  /// Use of FF_THREAD_FRAME will increase decoding delay by one frame per thread,
  /// so clients which cannot provide future frames should not use it.
  ///
  /// - encoding: Set by user, otherwise the default is used.
  /// - decoding: Set by user, otherwise the default is used.
  public var threadType: FFThreadType {
    get { FFThreadType(rawValue: cContext.thread_type) }
    set { cContextPtr.pointee.thread_type = newValue.rawValue }
  }

  /// thread count
  /// is used to decide how many independent tasks should be passed to execute()
  /// - encoding: Set by user.
  /// - decoding: Set by user.
  public var threadCount: Int32 {
    get { cContext.thread_count }
    set { cContextPtr.pointee.thread_count = newValue }
  }

  /// Which multithreading methods are in use by the codec.
  /// - encoding: Set by libavcodec.
  /// - decoding: Set by libavcodec.
  public var activeThreadType: FFThreadType {
    FFThreadType(rawValue: cContext.active_thread_type)
  }
}

extension AVCodecContext: AVClassSupport, AVOptionSupport {
  public static let `class` = AVClass(cClassPtr: avcodec_get_class())

  public func withUnsafeObjectPointer<T>(
    _ body: (UnsafeMutableRawPointer) throws -> T
  ) rethrows -> T {
    try body(cContextPtr)
  }
}

public struct FFThreadType: Equatable, OptionSet {
  /// Decode more than one frame at once
  public static let frame = FFThreadType(rawValue: FF_THREAD_FRAME)

  /// Decode more than one part of a single frame at once
  public static let slice = FFThreadType(rawValue: FF_THREAD_SLICE)

  public let rawValue: Int32

  public init(rawValue: Int32) { self.rawValue = rawValue }
}

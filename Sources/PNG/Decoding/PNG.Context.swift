extension PNG
{
    /// A decoding context.
    ///
    /// This type provides support for custom decoding schemes. You can
    /// work through an example of its usage in the
    /// [online decoding tutorial](https://github.com/tayloraswift/swift-png/tree/master/examples#online-decoding).
    public
    struct Context
    {
        /// The current image state.
        public private(set)
        var image:PNG.Image

        private
        var decoder:PNG.Decoder
    }
}
extension PNG.Context
{
    /// Creates a fresh decoding context.
    ///
    /// It is expected that client applications will initialize a decoding
    /// context upon encountering the first ``Chunk/IDAT`` chunk in the image.
    /// -   Parameter standard:
    ///     The PNG standard of the image being decoded. This should be ``Standard/ios``
    ///     if the image began with a ``Chunk/CgBI`` chunk, and ``Standard/common``
    ///     otherwise.
    /// -   Parameter header:
    ///     The header of the image being decoded. This is expected to have been
    ///     parsed from a previously-encountered ``Chunk/IHDR`` chunk.
    /// -   Parameter palette:
    ///     The palette of the image being decoded, if present. If not `nil`,
    ///     this is expected to have been parsed from a previously-encountered
    ///     ``Chunk/PLTE`` chunk.
    /// -   Parameter background:
    ///     The background descriptor of the image being decoded, if present.
    ///     If not `nil`, this is expected to have been parsed from a
    ///     previously-encountered ``Chunk/bKGD`` chunk.
    /// -   Parameter transparency:
    ///     The transparency descriptor of the image being decoded, if present.
    ///     If not `nil`, this is expected to have been parsed from a
    ///     previously-encountered ``Chunk/tRNS`` chunk.
    /// -   Parameter metadata:
    ///     A metadata instance. It is expected to contain metadata from all
    ///     previously-encountered ancillary chunks, with the exception of
    ///     ``Chunk/bKGD`` and ``Chunk/tRNS``.
    /// -   Parameter uninitialized:
    ///     Specifies if the ``image`` ``Image/storage`` should
    ///     be initialized. If `false`, the storage buffer will be initialized
    ///     to all zeros. This can be safely set to `true` if there is no need
    ///     to access the image while it is in a partially-decoded state.
    ///
    ///     The default value is `true`.
    public
    init?(standard:PNG.Standard, header:PNG.Header,
        palette:PNG.Palette?, background:PNG.Background?, transparency:PNG.Transparency?,
        metadata:PNG.Metadata,
        uninitialized:Bool = true)
    {
        guard let image:PNG.Image = PNG.Image.init(
            standard:       standard,
            header:         header,
            palette:        palette,
            background:     background,
            transparency:   transparency,
            metadata:       metadata,
            uninitialized:  uninitialized)
        else
        {
            return nil
        }

        self.image      = image
        self.decoder    = .init(standard: standard, interlaced: image.layout.interlaced)
    }
    /// Decompresses the contents of an ``Chunk/IDAT`` chunk, and updates
    /// the image state with the newly-decompressed image data.
    /// -   Parameter data:
    ///     The contents of the ``Chunk/IDAT`` chunk to process.
    /// -   Parameter overdraw:
    ///     If `true`, pixels that are not yet available will be filled-in
    ///     with values from nearby available pixels. This option only has an
    ///     effect for ``Layout/interlaced`` images.
    ///
    ///     The default value is `false`.
    public mutating
    func push(data:[UInt8], overdraw:Bool = false) throws
    {
        try self.decoder.push(data, size: self.image.size,
            pixel: self.image.layout.format.pixel,
            delegate: overdraw ?
        {
            let s:(x:Int, y:Int) = ($1.x == 0 ? 0 : 1, $1.y & 0b111 == 0 ? 0 : 1)
            self.image.assign(scanline: $0, at: $1, stride: $2.x)
            self.image.overdraw(            at: $1, brush: ($2.x >> s.x, $2.y >> s.y))
        }
        :
        {
            self.image.assign(scanline: $0, at: $1, stride: $2.x)
        })
    }
    /// Parses an ancillary chunk appearing after the last ``Chunk/IDAT``
    /// chunk, and adds it to the ``image`` ``Image/metadata``.
    ///
    /// This function validates the multiplicity of the given `chunk`, and
    /// its chunk ordering with respect to the ``Chunk/IDAT`` chunks. The
    /// caller is expected to have consumed all preceeding ``Chunk/IDAT``
    /// chunks in the image being decoded.
    ///
    /// Despite its name, this function can also accept an ``Chunk/IEND``
    /// critical chunk, in which case this function will verify that the
    /// compressed image data stream has been properly-terminated.
    /// -   Parameter chunk:
    ///     The chunk to process. Its `type` must be one of ``Chunk/tIME``,
    ///     ``Chunk/iTXt``, ``Chunk/tEXt``, ``Chunk/zTXt``, or ``Chunk/IEND``,
    ///     or a private application data chunk type.
    ///
    ///     All other chunk types will `throw` appropriate errors.
    public mutating
    func push(ancillary chunk:(type:PNG.Chunk, data:[UInt8])) throws
    {
        switch chunk.type
        {
        case .tIME:
            try PNG.Metadata.unique(assign: chunk.type, to: &self.image.metadata.time)
            {
                try .init(parsing: chunk.data)
            }
        case .iTXt:
            self.image.metadata.text.append(try .init(parsing: chunk.data))
        case .tEXt, .zTXt:
            self.image.metadata.text.append(try .init(parsing: chunk.data, unicode: false))
        case .CgBI, .IHDR, .PLTE, .bKGD, .tRNS, .hIST,
            .cHRM, .gAMA, .sRGB, .iCCP, .sBIT, .pHYs, .sPLT, .IDAT:
            throw PNG.DecodingError.unexpected(chunk: chunk.type, after: .IDAT)
        case .IEND:
            guard self.decoder.continue == nil
            else
            {
                throw PNG.DecodingError.incompleteImageDataCompressedDatastream
            }
        default:
            self.image.metadata.application.append(chunk)
        }
    }
}

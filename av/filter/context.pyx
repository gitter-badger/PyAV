from libc.string cimport memcpy

from av.audio.frame cimport AudioFrame, alloc_audio_frame
from av.dictionary cimport _Dictionary
from av.dictionary import Dictionary
from av.filter.pad cimport alloc_filter_pads
from av.frame cimport Frame
from av.utils cimport err_check
from av.video.frame cimport VideoFrame, alloc_video_frame


cdef object _cinit_sentinel = object()


cdef FilterContext make_filter_context():
    return FilterContext(_cinit_sentinel)


cdef class FilterContext(object):
    
    def __cinit__(self, sentinel):
        if sentinel is not _cinit_sentinel:
            raise RuntimeError('cannot construct FilterContext')

    def __repr__(self):
        return '<av.FilterContext %s of %r at 0x%x>' % (
            (repr(self.ptr.name) if self.ptr.name != NULL else '<NULL>') if self.ptr != NULL else 'None',
            self.filter.ptr.name if self.filter and self.filter.ptr != NULL else None,
            id(self),
        )
    
    property inputs:
        def __get__(self):
            if self._inputs is None:
                self._inputs = alloc_filter_pads(self.filter, self.ptr.input_pads, True, self)
            return self._inputs
    
    property outputs:
        def __get__(self):
            if self._outputs is None:
                self._outputs = alloc_filter_pads(self.filter, self.ptr.output_pads, False, self)
            return self._outputs
    
    property name:
        def __get__(self):
            if not self.ptr:
                raise RuntimeError('no pointer')
            if self.ptr.name != NULL:
                return self.ptr.name
    
    def init(self, args=None, **kwargs):
        
        if self.inited:
            raise ValueError('already inited')
        if args and kwargs:
            raise ValueError('cannot init from args and kwargs')
        
        cdef _Dictionary dict_ = None
        cdef char *c_args = NULL
        if args or not kwargs:
            if args:
                c_args = args
            err_check(lib.avfilter_init_str(self.ptr, c_args))
        else:
            dict_ = Dictionary(kwargs)
            err_check(lib.avfilter_init_dict(self.ptr, &dict_.ptr))
        
        self.inited = True
        if dict_:
            raise ValueError('unused config: %s' % ', '.join(sorted(dict_)))
    
    def link(self, int output_idx, FilterContext input_, int input_idx):
        err_check(lib.avfilter_link(self.ptr, output_idx, input_.ptr, input_idx))
    
    def push(self, Frame frame):
        if self.filter.name != 'buffer':
            raise RuntimeError('cannot push on %s' % self.filter.name)
        err_check(lib.av_buffersrc_write_frame(self.ptr, frame.ptr))
    
    def pull(self):
        
        cdef Frame frame
        if self.filter.name == 'buffersink':
            frame = alloc_video_frame()
        elif self.filter.name == 'abuffersink':
            frame = alloc_audio_frame()
        else:
            # TODO: defer this request to our inputs.
            raise RuntimeError('cannot pull on %s' % self.filter.name)
        
        self.graph.configure()
        
        err_check(lib.av_buffersink_get_frame(self.ptr, frame.ptr))
        frame._init_properties()
        return frame

        
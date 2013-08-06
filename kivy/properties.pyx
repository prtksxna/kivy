'''
Properties
==========

The *Properties* classes are used when you create a
:class:`~kivy.event.EventDispatcher`.

.. warning::
        Kivy's Properties are **not to be confused** with Python's
        properties (i.e. the ``@property`` decorator and the <property> type).

Kivy's property classes support:

    Value Checking / Validation
        When you assign a new value to a property, the value is checked to
        pass constraints implemented in the class such as validation. For
        example, validation for :class:`OptionProperty` will make sure that
        the value is in a predefined list of possibilities. Validation for
        :class:`NumericProperty` will check that your value is a numeric type.
        This prevents many errors early on.

    Observer Pattern
        You can specify what should happen when a property's value changes.
        You can bind your own function as a callback to changes of a
        :class:`Property`. If, for example, you want a piece of code to be
        called when a widget's :class:`~kivy.uix.widget.Widget.pos` property
        changes, you can :class:`~kivy.event.EventDispatcher.bind` a function
        to it.

    Better Memory Management
        The same instance of a property is shared across multiple widget
        instances.

Comparison Python / Kivy
------------------------

Basic example
~~~~~~~~~~~~~

Let's compare Python and Kivy properties by creating a Python class with 'a'
as a float::

    class MyClass(object):
        def __init__(self, a=1.0):
            super(MyClass, self).__init__()
            self.a = a

With Kivy, you can do::

    class MyClass(EventDispatcher):
        a = NumericProperty(1.0)


Value checking
~~~~~~~~~~~~~~

If you wanted to add a check such a minimum / maximum value allowed for a
property, here is a possible implementation in Python::

    class MyClass(object):
        def __init__(self, a=1):
            super(MyClass, self).__init__()
            self._a = 0
            self.a_min = 0
            self.a_max = 100
            self.a = a

        def _get_a(self):
            return self._a
        def _set_a(self, value):
            if value < self.a_min or value > self.a_max:
                raise ValueError('a out of bounds')
            self._a = a
        a = property(_get_a, _set_a)

The disadvantage is you have to do that work yourself. And it becomes
laborious and complex if you have many properties.
With Kivy, you can simplify like this::

    class MyClass(EventDispatcher):
        a = BoundedNumericProperty(1, min=0, max=100)

That's all!


Error Handling
~~~~~~~~~~~~~~

If setting a value would otherwise raise a ValueError, you have two options to
handle the error gracefully within the property.  An errorvalue is a substitute
for the invalid value. An errorhandler is a callable (single argument function
or lambda) which can return a valid substitute.

errorhandler parameter::

    # simply returns 0 if the value exceeds the bounds
    bnp = BoundedNumericProperty(0, min=-500, max=500, errorvalue=0)

errorvalue parameter::

    # returns a the boundary value when exceeded
    bnp = BoundedNumericProperty(0, min=-500, max=500,
        errorhandler=lambda x: 500 if x > 500 else -500)


Conclusion
~~~~~~~~~~

Kivy properties are easier to use than the standard ones. See the next chapter
for examples of how to use them :)


Observe Properties changes
--------------------------

As we said in the beginning, Kivy's Properties implement the `Observer pattern
<http://en.wikipedia.org/wiki/Observer_pattern>`_. That means you can
:meth:`~kivy.event.EventDispatcher.bind` to a property and have your own
function called when the value changes.

Multiple ways are available to observe the changes.

Observe using bind()
~~~~~~~~~~~~~~~~~~~~

You can observe a property change by using the bind() method, outside the
class::

    class MyClass(EventDispatcher):
        a = NumericProperty(1)

    def callback(instance, value):
        print('My callback is call from', instance)
        print('and the a value changed to', value)

    ins = MyClass()
    ins.bind(a=callback)

    # At this point, any change to the a property will call your callback.
    ins.a = 5    # callback called
    ins.a = 5    # callback not called, because the value didnt change
    ins.a = -1   # callback called

Observe using 'on_<propname>'
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you created the class yourself, you can use the 'on_<propname>' callback::

    class MyClass(EventDispatcher):
        a = NumericProperty(1)

        def on_a(self, instance, value):
            print('My property a changed to', value)

.. warning::

    Be careful with 'on_<propname>'. If you are creating such a callback on a
    property you are inherit, you must not forget to call the subclass
    function too.






'''

__all__ = ('Property',
           'NumericProperty', 'StringProperty', 'ListProperty',
           'ObjectProperty', 'BooleanProperty', 'BoundedNumericProperty',
           'OptionProperty', 'ReferenceListProperty', 'AliasProperty',
           'DictProperty', 'VariableListProperty')

include "graphics/config.pxi"

from weakref import ref
from kivy.compat import string_types

from kivy.compat import string_types
from kivy.logger import Logger


cdef float g_dpi = -1
cdef float g_density = -1
cdef float g_fontscale = -1

NUMERIC_FORMATS = ('in', 'px', 'dp', 'sp', 'pt', 'cm', 'mm')

cpdef float dpi2px(value, ext):
    # 1in = 2.54cm = 25.4mm = 72pt = 12pc
    global g_dpi, g_density, g_fontscale
    if g_dpi == -1:
        from kivy.metrics import Metrics
        g_dpi = Metrics.dpi
        g_density = Metrics.density
        g_fontscale = Metrics.fontscale
    cdef float rv = float(value)
    if ext == 'in':
        return rv * g_dpi
    elif ext == 'px':
        return rv
    elif ext == 'dp':
        return rv * g_density
    elif ext == 'sp':
        return rv * g_density * g_fontscale
    elif ext == 'pt':
        return rv * g_dpi / 72.
    elif ext == 'cm':
        return rv * g_dpi / 2.54
    elif ext == 'mm':
        return rv * g_dpi / 25.4

cdef class Property:
    '''Base class for building more complex properties.

    This class handles all the basic setters and getters, None type handling,
    the observer list and storage initialisation. This class should not be
    directly instantiated.

    By default, a :class:`Property` always takes a default value::

        class MyObject(Widget):

            hello = Property('Hello world')

    The default value must be a value that agrees with the Property type. For
    example, you can't set a list to a :class:`StringProperty`, because the
    StringProperty will check the default value.

    None is a special case: you can set the default value of a Property to
    None, but you can't set None to a property afterward.  If you really want
    to do that, you must declare the Property with `allownone=True`::

        class MyObject(Widget):

            hello = ObjectProperty(None, allownone=True)

        # then later
        a = MyObject()
        a.hello = 'bleh' # working
        a.hello = None # working too, because allownone is True.

    :Parameters:
        `errorhandler`: callable
            If set, must take a single argument and return a valid substitute
            value
        `errorvalue`: object
            If set, will replace an invalid property value (overrides
            errorhandler)

    .. versionchanged:: 1.4.2
        Parameters errorhandler and errorvalue added
    '''

    def __cinit__(self):
        self._name = ''
        self.allownone = 0
        self.defaultvalue = None
        self.errorvalue = None
        self.errorhandler = None
        self.errorvalue_set = 0


    def __init__(self, defaultvalue, **kw):
        self.defaultvalue = defaultvalue
        self.allownone = <int>kw.get('allownone', 0)
        self.errorvalue = kw.get('errorvalue', None)
        self.errorhandler = kw.get('errorhandler', None)

        if 'errorvalue' in kw:
            self.errorvalue_set = 1

        if 'errorhandler' in kw and not callable(self.errorhandler):
            raise ValueError('errorhandler %s not callable' % self.errorhandler)


    property name:
        def __get__(self):
            return self._name

    cdef init_storage(self, EventDispatcher obj, PropertyStorage storage):
        storage.value = self.convert(obj, self.defaultvalue)
        storage.observers = []

    cpdef link(self, EventDispatcher obj, str name):
        '''Link the instance with its real name.

        .. warning::

            Internal usage only.

        When a widget is defined and uses a :class:`Property` class, the
        creation of the property object happens, but the instance doesn't know
        anything about its name in the widget class::

            class MyWidget(Widget):
                uid = NumericProperty(0)

        In this example, the uid will be a NumericProperty() instance, but the
        property instance doesn't know its name. That's why :func:`link` is
        used in Widget.__new__. The link function is also used to create the
        storage space of the property for this specific widget instance.
        '''
        cdef PropertyStorage d = PropertyStorage()
        self._name = name
        obj.__storage[name] = d
        self.init_storage(obj, d)

    cpdef link_deps(self, EventDispatcher obj, str name):
        pass

    cpdef bind(self, EventDispatcher obj, observer):
        '''Add a new observer to be called only when the value is changed.
        '''
        cdef PropertyStorage ps = obj.__storage[self._name]
        if observer not in ps.observers:
            ps.observers.append(observer)

    cpdef unbind(self, EventDispatcher obj, observer):
        '''Remove the observer from our widget observer list.
        '''
        cdef PropertyStorage ps = obj.__storage[self._name]
        for item in ps.observers[:]:
            if item == observer:
                ps.observers.remove(item)

    def __set__(self, EventDispatcher obj, val):
        self.set(obj, val)

    def __get__(self, EventDispatcher obj, objtype):
        if obj is None:
            return self
        return self.get(obj)

    cdef compare_value(self, a, b):
        return a == b

    cpdef set(self, EventDispatcher obj, value):
        '''Set a new value for the property.
        '''
        cdef PropertyStorage ps = obj.__storage[self._name]
        value = self.convert(obj, value)
        realvalue = ps.value
        if self.compare_value(realvalue, value):
            return False

        try:
            self.check(obj, value)
        except ValueError as e:
            if self.errorvalue_set == 1:
                value = self.errorvalue
                self.check(obj, value)
            elif self.errorhandler is not None:
                value = self.errorhandler(value)
                self.check(obj, value)
            else:
                raise e

        ps.value = value
        self.dispatch(obj)
        return True

    cpdef get(self, EventDispatcher obj):
        '''Return the value of the property.
        '''
        cdef PropertyStorage ps = obj.__storage[self._name]
        return ps.value

    #
    # Private part
    #

    cdef check(self, EventDispatcher obj, x):
        '''Check if the value is correct or not, depending on the settings of
        the property class.

        :Returns:
            bool, True if the value correctly validates.
        '''
        if x is None:
            if not self.allownone:
                raise ValueError('None is not allowed for %s.%s' % (
                    obj.__class__.__name__,
                    self.name))
            else:
                return True

    cdef convert(self, EventDispatcher obj, x):
        '''Convert the initial value to a correctly validating value.
        Can be used for multiple types of arguments, simplifying to only one.
        '''
        return x

    cpdef dispatch(self, EventDispatcher obj):
        '''Dispatch the value change to all observers.

        .. versionchanged:: 1.1.0
            The method is now accessible from Python.

        This can be used to force the dispatch of the property, even if the
        value didn't change::

            button = Button()
            # get the Property class instance
            prop = button.property('text')
            # dispatch this property on the button instance
            prop.dispatch(button)

        '''
        cdef PropertyStorage ps = obj.__storage[self._name]
        if len(ps.observers):
            value = ps.value
            for observer in ps.observers:
                observer(obj, value)


    # TODO: Can the op_info arg be added to dispatch() without problems?

    cpdef dispatch_with_op_info(self, EventDispatcher obj, op_info):
        '''Dispatch the value change to all observers.

        .. versionadded:: 1.8

        '''
        cdef PropertyStorage ps = obj.__storage[self._name]
        if len(ps.observers):
            value = ps.value
            for observer in ps.observers:
                observer(obj, value, op_info)


cdef class NumericProperty(Property):
    '''Property that represents a numeric value.

    The NumericProperty accepts only int or float.

    >>> wid = Widget()
    >>> wid.x = 42
    >>> print(wid.x)
    42
    >>> wid.x = "plop"
     Traceback (most recent call last):
       File "<stdin>", line 1, in <module>
       File "properties.pyx", line 93, in kivy.properties.Property.__set__
       File "properties.pyx", line 111, in kivy.properties.Property.set
       File "properties.pyx", line 159, in kivy.properties.NumericProperty.check
     ValueError: NumericProperty accept only int/float

    .. versionchanged:: 1.4.1
        NumericProperty can now accept custom text and tuple value to indicate a
        type, like "in", "pt", "px", "cm", "mm", in the format: '10pt' or (10,
        'pt').

    '''
    def __init__(self, defaultvalue=0, **kw):
        super(NumericProperty, self).__init__(defaultvalue, **kw)

    cdef init_storage(self, EventDispatcher obj, PropertyStorage storage):
        storage.numeric_fmt = 'px'
        Property.init_storage(self, obj, storage)

    cdef check(self, EventDispatcher obj, value):
        if Property.check(self, obj, value):
            return True
        if type(value) not in (int, float, long):
            raise ValueError('%s.%s accept only int/float/long (got %r)' % (
                obj.__class__.__name__,
                self.name, value))

    cdef convert(self, EventDispatcher obj, x):
        if x is None:
            return x
        tp = type(x)
        if tp is int or tp is float or tp is long:
            return x
        if tp is tuple or tp is list:
            if len(x) != 2:
                raise ValueError('%s.%s must have 2 components (got %r)' % (
                    obj.__class__.__name__,
                    self.name, x))
            return self.parse_list(obj, x[0], <str>x[1])
        elif tp is str:
            return self.parse_str(obj, x)
        else:
            raise ValueError('%s.%s have an invalid format (got %r)' % (
                obj.__class__.__name__,
                self.name, x))

    cdef float parse_str(self, EventDispatcher obj, value):
        return self.parse_list(obj, value[:-2], <str>value[-2:])

    cdef float parse_list(self, EventDispatcher obj, value, str ext):
        cdef PropertyStorage ps = obj.__storage[self._name]
        ps.numeric_fmt = ext
        return dpi2px(value, ext)

    def get_format(self, EventDispatcher obj):
        '''
        Return the format used for Numeric calculation. Default is px (mean
        the value have not been changed at all). Otherwise, it can be one of
        'in', 'pt', 'cm', 'mm'.
        '''
        cdef PropertyStorage ps = obj.__storage[self._name]
        return ps.numeric_fmt


cdef class StringProperty(Property):
    '''Property that represents a string value.

    Only a string or unicode is accepted.
    '''

    def __init__(self, defaultvalue='', **kw):
        super(StringProperty, self).__init__(defaultvalue, **kw)

    cdef check(self, EventDispatcher obj, value):
        if Property.check(self, obj, value):
            return True
        if not isinstance(value, string_types):
            raise ValueError('%s.%s accept only str' % (
                obj.__class__.__name__,
                self.name))

cdef inline void observable_list_dispatch(object self):
    cdef Property prop = self.prop
    obj = self.obj()
    if obj is not None:
        prop.dispatch(obj)


class ObservableList(list):
    # Internal class to observe changes inside a native python list.
    def __init__(self, *largs):
        self.prop = largs[0]
        self.obj = ref(largs[1])
        super(ObservableList, self).__init__(*largs[2:])

    def __setitem__(self, key, value):
        list.__setitem__(self, key, value)
        observable_list_dispatch(self)

    def __delitem__(self, key):
        list.__delitem__(self, key)
        observable_list_dispatch(self)

    def __setslice__(self, *largs):
        list.__setslice__(self, *largs)
        observable_list_dispatch(self)

    def __delslice__(self, *largs):
        list.__delslice__(self, *largs)
        observable_list_dispatch(self)

    def __iadd__(self, *largs):
        list.__iadd__(self, *largs)
        observable_list_dispatch(self)

    def __imul__(self, *largs):
        list.__imul__(self, *largs)
        observable_list_dispatch(self)

    def append(self, *largs):
        list.append(self, *largs)
        observable_list_dispatch(self)

    def remove(self, *largs):
        list.remove(self, *largs)
        observable_list_dispatch(self)

    def insert(self, *largs):
        list.insert(self, *largs)
        observable_list_dispatch(self)

    def pop(self, *largs):
        cdef object result = list.pop(self, *largs)
        observable_list_dispatch(self)
        return result

    def extend(self, *largs):
        list.extend(self, *largs)
        observable_list_dispatch(self)

    # TODO: Added **kwds because of complaining when key=lambda... was passed.
    #       What is the official signature?
    #def sort(self, *largs):
    def sort(self, *largs, **kwds):
        list.sort(self, *largs, **kwds)
        observable_list_dispatch(self)

    def reverse(self, *largs):
        list.reverse(self, *largs)
        observable_list_dispatch(self)

    def batch_delete(self, indices):
        for index in indices:
            list.__delitem__(self, index)
        observable_list_dispatch(self)


cdef class ListProperty(Property):
    '''Property that represents a list.

    Only lists are allowed. Tuple or any other classes are forbidden.

    .. versionchanged:: 1.8.0

        The following change does not affect the API. It has to do with
        internal event dispatching. It may be interesting to widget developers.

        A new class, OpObservableList, is defined in this module, complimenting
        the original ObservableList.  Whereas the new OpObservableList
        dispatches change events on a per op basis, the original ObservableList
        does gross dispatching, so that there is no detailed change information
        available to widgets.  

        A new cls argument is checked, and if not defined, the original
        ObservableList is used. Otherwise, the OpObservableList is used.

        The default behavior remains the same: an observer sees a change event
        when either the list is reset or when it changes in some way. The new
        more detailed change info is not available, but is not always needed.
    '''
    def __init__(self, defaultvalue=None, **kw):
        defaultvalue = defaultvalue or []

        self.cls = kw.get('cls', ObservableList)

        super(ListProperty, self).__init__(defaultvalue, **kw)

    cpdef link(self, EventDispatcher obj, str name):
        Property.link(self, obj, name)
        cdef PropertyStorage ps = obj.__storage[self._name]
        ps.value = self.cls(self, obj, ps.value)

    cdef check(self, EventDispatcher obj, value):
        if Property.check(self, obj, value):
            return True
        if type(value) is not self.cls:
            raise ValueError('{}.{} accept only {}'.format(
                obj.__class__.__name__,
                self.name,
                self.cls.__name__))

    cpdef set(self, EventDispatcher obj, value):
        value = self.cls(self, obj, value)
        Property.set(self, obj, value)

cdef inline void observable_dict_dispatch(object self):
    cdef Property prop = self.prop
    prop.dispatch(self.obj)


class ObservableDict(dict):
    # Internal class to observe changes inside a native python dict.
    def __init__(self, *largs):
        self.prop = largs[0]
        self.obj = largs[1]
        super(ObservableDict, self).__init__(*largs[2:])

    def _weak_return(self, item):
        if isinstance(item, ref):
            return item()
        return item

    def __getattr__(self, attr):
        try:
            return self._weak_return(self.__getitem__(attr))
        except KeyError:
            try:
                return self._weak_return(
                                super(ObservableDict, self).__getattr__(attr))
            except AttributeError:
                raise KeyError(attr)

    def __setattr__(self, attr, value):
        if attr in ('prop', 'obj'):
            super(ObservableDict, self).__setattr__(attr, value)
            return
        self.__setitem__(attr, value)

    def __setitem__(self, key, value):
        if value is None:
            # remove attribute if value is None
            # is this really needed?
            # NOTE: OpObservableDict allows None values.
            self.__delitem__(key)
        else:
            dict.__setitem__(self, key, value)
        observable_dict_dispatch(self)

    def __delitem__(self, key):
        dict.__delitem__(self, key)
        observable_dict_dispatch(self)

    def clear(self, *largs):
        dict.clear(self, *largs)
        observable_dict_dispatch(self)

    def pop(self, *largs):
        cdef object result = dict.pop(self, *largs)
        observable_dict_dispatch(self)
        return result

    def popitem(self, *largs):
        cdef object result = dict.popitem(self, *largs)
        observable_dict_dispatch(self)
        return result

    def setdefault(self, *largs):
        dict.setdefault(self, *largs)
        observable_dict_dispatch(self)

    def update(self, *largs):
        dict.update(self, *largs)
        observable_dict_dispatch(self)


cdef class DictProperty(Property):
    '''Property that represents a dict.

    Only dict are allowed. Any other classes are forbidden.

    .. versionchanged:: 1.8.0

        The following change does not affect the API. It has to do with
        internal event dispatching. It may be interesting to widget developers.

        A new class, OpObservableDict, is defined in this module, complimenting
        the original ObservableDict.  Whereas the new OpObservableDict
        dispatches change events on a per op basis, the original ObservableDict
        does gross dispatching, so that there is no detailed change information
        available to widgets.
        
        A new cls argument is checked, and if not defined, the original
        ObservableDict is used. Otherwise, the OpObservableDict is used.

        The default behavior remains the same: an observer sees a change event
        when either the dict is reset or when it changes in some way. The new
        more detailed change info is not available, but is not always needed.
    '''
    def __init__(self, defaultvalue=None, **kw):
        defaultvalue = defaultvalue or {}

        self.cls = kw.get('cls', ObservableDict)

        super(DictProperty, self).__init__(defaultvalue, **kw)

    cpdef link(self, EventDispatcher obj, str name):
        Property.link(self, obj, name)
        cdef PropertyStorage ps = obj.__storage[self._name]
        ps.value = self.cls(self, obj, ps.value)

    cdef check(self, EventDispatcher obj, value):
        if Property.check(self, obj, value):
            return True
        if type(value) is not self.cls:
            raise ValueError('{}.{} accept only {}'.format(
                obj.__class__.__name__,
                self.name,
                self.cls.__name__))

    cpdef set(self, EventDispatcher obj, value):
        value = self.cls(self, obj, value)
        Property.set(self, obj, value)


class ListOpInfo(object):
    '''Holds change info about an OpObservableList instance.
    '''

    def __init__(self, op_name, start_index, end_index):
        self.op_name = op_name
        self.start_index = start_index
        self.end_index = end_index


cdef inline void op_observable_list_dispatch(object self, object op_info):
    cdef Property prop = self.prop
    obj = self.obj()
    if obj is not None:
        prop.dispatch_with_op_info(obj, op_info)


class OpObservableList(list):
    '''This class is used as a cls argument to
    :class:`~kivy.properties.ListProperty` as an alternative to the default
    :class:`~kivy.properties.ObservableList`.

    :class:`~kivy.properties.OpObservableList` is used to record
    change info about a list instance in a more detailed, per-op manner than a
    :class:`~kivy.properties.ObservableList` instance, which dispatches grossly
    for any change, but with no info about the change.

    Range-observing and granular (per op) data is stored in op_info and
    sort_op_info for use by an observer.

    .. versionchanged:: 1.8.0

        Added, along with modifications to ListProperty to allow its use.
        ListOpInfo and ListOpHander were also added.

    '''

    def __init__(self, *largs):
        # largs are:
        #
        #     ListProperty instance
        #     Owner instance (e.g., an adapter)
        #     value
        #
        self.prop = largs[0]
        self.obj = ref(largs[1])

        super(OpObservableList, self).__init__(*largs[2:])

    # TODO: setitem and delitem are supposed to handle slices, instead of the
    #       deprecated setslice() and delslice() methods.
    def __setitem__(self, key, value):
        list.__setitem__(self, key, value)
        op_observable_list_dispatch(self,
               ListOpInfo('OOL_setitem', key, key))

    def __delitem__(self, key):
        list.__delitem__(self, key)
        op_observable_list_dispatch(self,
               ListOpInfo('OOL_delitem', key, key))

    def __setslice__(self, *largs):
        #
        # Python docs:
        #
        #     operator.__setslice__(a, b, c, v)
        #
        #     Set the slice of a from index b to index c-1 to the sequence v.
        #
        #     Deprecated since version 2.6: This function is removed in Python
        #     3.x. Use setitem() with a slice index.
        #
        start_index = largs[0]
        end_index = largs[1] - 1
        list.__setslice__(self, *largs)
        op_observable_list_dispatch(self,
                ListOpInfo('OOL_setslice', start_index, end_index))

    def __delslice__(self, *largs):
        # Delete the slice of a from index b to index c-1. del a[b:c],
        # where the args here are b and c.
        # Also deprecated.
        start_index = largs[0]
        end_index = largs[1] - 1
        list.__delslice__(self, *largs)
        op_observable_list_dispatch(self,
                ListOpInfo('OOL_delslice', start_index, end_index))

    def __iadd__(self, *largs):
        start_index = len(self)
        end_index = start_index + len(largs) - 1
        list.__iadd__(self, *largs)
        op_observable_list_dispatch(self,
                ListOpInfo('OOL_iadd', start_index, end_index))

    def __imul__(self, *largs):
        num = largs[0]
        start_index = len(self)
        end_index = start_index + (len(self) * num)
        list.__imul__(self, *largs)
        op_observable_list_dispatch(self,
                ListOpInfo('OOL_imul', start_index, end_index))

    def append(self, *largs):
        index = len(self)
        list.append(self, *largs)
        op_observable_list_dispatch(self,
                ListOpInfo('OOL_append', index, index))

    def remove(self, *largs):
        index = self.index(largs[0])
        list.remove(self, *largs)
        op_observable_list_dispatch(self,
                ListOpInfo('OOL_remove', index, index))

    def insert(self, *largs):
        index = largs[0]
        list.insert(self, *largs)
        op_observable_list_dispatch(self,
                ListOpInfo('OOL_insert', index, index))

    def pop(self, *largs):
        if largs:
            index = largs[0]
        else:
            index = len(self) - 1
        result = list.pop(self, *largs)
        op_observable_list_dispatch(self,
                ListOpInfo('OOL_pop', index, index))
        return result

    def extend(self, *largs):
        start_index = len(self)
        end_index = start_index + len(largs[0]) - 1
        list.extend(self, *largs)
        op_observable_list_dispatch(self,
                ListOpInfo('OOL_extend', start_index, end_index))

    def start_sort_op(self, op, *largs, **kwds):
        self.sort_largs = largs
        self.sort_kwds = kwds
        self.sort_op = op

        # Trigger the "sort is starting" callback to the adapter, so it can do
        # pre-sort writing of the current arrangement of indices and data.
        op_observable_list_dispatch(self,
                ListOpInfo('OOL_sort_start', 0, 0))

    def finish_sort_op(self):
        largs = self.sort_largs
        kwds = self.sort_kwds
        sort_op = self.sort_op

        # Perform the sort.
        if sort_op == 'OOL_sort':
            list.sort(self, *largs, **kwds)
        else:
            list.reverse(self, *largs)

        # Finalize. Will go back to adapter for handling cached_views,
        # selection, and prep for triggering data_changed on ListView.
        op_observable_list_dispatch(self,
                ListOpInfo(sort_op, 0, len(self) - 1))

    def sort(self, *largs, **kwds):
        self.start_sort_op('OOL_sort', *largs, **kwds)

    def reverse(self, *largs):
        self.start_sort_op('OOL_reverse', *largs)

    def batch_delete(self, indices):
        for index in indices:
            list.__delitem__(self, index)
        op_observable_list_dispatch(self,
                ListOpInfo('batch_delete', 0, len(self) - 1))

class ListOpHandler(object):
    '''A :class:`ListOpHandler` reacts to the following operations that are
    possible for a OpObservableList (OOL) instance, categorized as
    follows:

        Adding and inserting:

            OOL_append
            OOL_extend
            OOL_insert

        Applying operator:

            OOL_iadd
            OOL_imul

        Setting:

            OOL_setitem
            OOL_setslice

        Deleting:

            OOL_delitem
            OOL_delslice
            OOL_remove
            OOL_pop

        Sorting:

            OOL_sort
            OOL_reverse
    '''

    def data_changed(self, *args):
        '''This method receives the callback for a data change to
        self.source_list, and calls the appropriate methods, reacting to
        cover the possible operation events listed above.
        '''
        pass


class DictOpInfo(object):
    '''Holds change info about an OpObservableDict instance.
    '''

    def __init__(self, op_name, keys):
        self.op_name = op_name
        self.keys = keys


cdef inline void op_observable_dict_dispatch(object self,
                                             object op_info):
    cdef Property prop = self.prop
    prop.dispatch_with_op_info(self.obj, op_info)


class OpObservableDict(dict):
    '''This class is used as a cls argument to
    :class:`~kivy.properties.DictProperty` as an alternative to the default
    :class:`~kivy.properties.ObservableDict`.

    :class:`~kivy.properties.OpObservableDict` is used to record
    change info about a dict instance in a more detailed, per-op manner than a
    :class:`~kivy.properties.ObservableDict` instance, which dispatches grossly
    for any change, but with no info about the change.

    Range-observing and granular (per op) data is stored in op_info for use by
    an observer.

    .. versionchanged:: 1.8.0

        Added, along with modifications to DictProperty to allow its use.
        DictOpInfo and DictOpHander were also added.

    '''

    def __init__(self, *largs):
        # largs are:
        #
        #     DictProperty instance
        #     Owner instance (e.g., an adapter)
        #     value
        #
        self.prop = largs[0]
        self.obj = largs[1]

        super(OpObservableDict, self).__init__(*largs[2:])

        #self.data = largs[2]

        self.op_info = None

    def _weak_return(self, item):
        if isinstance(item, ref):
            return item()
        return item

    def __getattr__(self, attr):
        try:
            return self._weak_return(self.__getitem__(attr))
        except KeyError:
            try:
                return self._weak_return(
                    super(OpObservableDict, self).__getattr__(attr))
            except AttributeError:
                raise KeyError(attr)

    def __setattr__(self, attr, value):
        if attr in ('prop', 'obj', 'op_info'):
            super(OpObservableDict, self).__setattr__(attr, value)
            return
        self.__setitem__(attr, value)

    def __setitem__(self, key, value):

        # TODO: This is the code in ObservableDict.__setitem__. Note the
        #       handling for None. Resurrect OOD_setitem_del?
        #if value is None:
        #    # remove attribute if value is None
        #    # is this really needed?
        #    # NOTE: OpObservableDict allows None values.
        #    self.__delitem__(key)
        #else:
        #    dict.__setitem__(self, key, value)

        if key in self.keys():
            op_info = DictOpInfo('OOD_setitem_set', (key, ))
        else:
            op_info = DictOpInfo('OOD_setitem_add', (key, ))
        dict.__setitem__(self, key, value)
        op_observable_dict_dispatch(self, op_info)

    def __delitem__(self, key):
        dict.__delitem__(self, key)
        op_observable_dict_dispatch(self,
                DictOpInfo('OOD_delitem', (key, )))

    def clear(self, *largs):
        # Store a local copy of self, because the clear() will
        # remove everything, including it. Restore it after the clear.
        recorder = self
        dict.clear(self, *largs)
        self = recorder
        op_observable_dict_dispatch(self,
                DictOpInfo('OOD_clear', (None, )))

    def pop(self, *largs):
        key = largs[0]

        # This is pop on a specific key. If that key is absent, the second arg
        # is returned. If there is no second arg in that case, a key error is
        # raised. But the key is always largs[0], so store that.
        # s.pop([i]) is same as x = s[i]; del s[i]; return x
        result = dict.pop(self, *largs)
        op_observable_dict_dispatch(self,
                DictOpInfo('OOD_pop', (key, )))
        return result

    def popitem(self, *largs):
        # From python docs, "Remove and return an arbitrary (key, value) pair
        # from the dictionary." From other reading, arbitrary here effectively
        # means "random" in the loose sense, of removing on the basis of how
        # items are stored internally as links -- for truely random ops, use
        # the proper random module. Nevertheless, the item is deleted and
        # returned.  If the dict is empty, a key error is raised.

        last = None
        if len(largs):
            last = largs[0]

        Logger.info('OOD: popitem, last = {0}'.format(last))

        if not self.keys():
            raise KeyError('dictionary is empty')

        key = next((self) if last else iter(self))

        Logger.info('OOD: popitem, key = {0}'.format(key))

        value = self[key]

        Logger.info('OOD: popitem, value = {0}'.format(value))

        # NOTE: We have no set to self.op_info for
        # OOD_popitem, because the following del self[key] will trigger a
        # OOD_delitem, which should suffice for the owning collection view
        # (e.g., ListView) to react as it would for OOD_popitem. If we set
        # self.op_info with OOD_popitem here, we get a
        # double-callback.
        del self[key]
        return key, value

    def setdefault(self, *largs):
        present_keys = self.keys()
        key = largs[0]
        op_info = None
        if not key in present_keys:
            op_info = DictOpInfo('OOD_setdefault', (key, ))
        result = dict.setdefault(self, *largs)
        if op_info:
            op_observable_dict_dispatch(self, op_info)
        return result

    def update(self, *largs):
        op_info = None
        present_keys = self.keys()
        if present_keys:
            op_info = DictOpInfo(
                    'OOD_update',
                    list(set(largs[0].keys()) - set(present_keys)))
        dict.update(self, *largs)
        if op_info:
            op_observable_dict_dispatch(self, op_info)

    # TODO: This was exposed through the adapter, but now we are doing it here.
    def insert(self, key, value):
        dict.__setitem__(self, key, value)
        op_observable_dict_dispatch(self,
                DictOpInfo('OOD_insert', (key, )))


class DictOpHandler(object):
    '''A :class:`DictOpHandler` may react to the following operations that are
    possible for a OpObservableDict instance:

        Adding:

            OOD_setitem_add
            OOD_setdefault
            OOD_update

        Setting:

            OOD_setitem_set

        Deleting:

            OOD_delitem
            OOD_pop
            OOD_popitem
            OOD_clear
    '''

    def data_changed(self, *args):
        '''This method receives the callback for a data change to
        self.source_dict, and calls the appropriate methods, reacting to
        cover the possible operation events listed above.
        '''
        pass


cdef class ObjectProperty(Property):
    '''Property that represents a Python object.

    :Parameters:
        `baseclass`: object
            This will be used for: `isinstance(value, baseclass)`.

    .. warning::

        To mark the property as changed, you must reassign a new python object.

        Be careful of using tuples, for instance: if a tuple were used in
        setting a delete_op ObjectProperty instance to mark a list delete
        operation with (0, 0) for start and end indices, repeated delete ops
        set with (0, 0) would not dispatch for a change, because in
        :class:`~kivy.properties.Property` the comparison for change is made
        with the == operator, not the is comparison. Use a class to hold the
        start and stop indices instead.

    .. versionchanged:: 1.7.0

        `baseclass` parameter added.
    '''
    def __init__(self, defaultvalue=None, **kw):
        self.baseclass = kw.get('baseclass', object)
        super(ObjectProperty, self).__init__(defaultvalue, **kw)

    cdef check(self, EventDispatcher obj, value):
        if Property.check(self, obj, value):
            return True
        if not isinstance(value, self.baseclass):
            raise ValueError('%s.%s accept only Python object' % (
                obj.__class__.__name__,
                self.name))

cdef class BooleanProperty(Property):
    '''Property that represents only a boolean value.
    '''

    def __init__(self, defaultvalue=True, **kw):
        super(BooleanProperty, self).__init__(defaultvalue, **kw)

    cdef check(self, EventDispatcher obj, value):
        if Property.check(self, obj, value):
            return True
        if not isinstance(value, object):
            raise ValueError('%s.%s accept only bool' % (
                obj.__class__.__name__,
                self.name))

cdef class BoundedNumericProperty(Property):
    '''Property that represents a numeric value within a minimum bound and/or
    maximum bound -- within a numeric range.

    :Parameters:
        `min`: numeric
            If set, minimum bound will be used, with the value of min
        `max`: numeric
            If set, maximum bound will be used, with the value of max
    '''
    def __cinit__(self):
        self.use_min = 0
        self.use_max = 0
        self.min = 0
        self.max = 0
        self.f_min = 0.0
        self.f_max = 0.0

    def __init__(self, *largs, **kw):
        value = kw.get('min', None)
        if value is None:
            self.use_min = 0
        elif type(value) is float:
                self.use_min = 2
                self.f_min = value
        else:
            self.use_min = 1
            self.min = value

        value = kw.get('max', None)
        if value is None:
            self.use_max = 0
        elif type(value) is float:
            self.use_max = 2
            self.f_max = value
        else:
            self.use_max = 1
            self.max = value

        Property.__init__(self, *largs, **kw)

    cdef init_storage(self, EventDispatcher obj, PropertyStorage storage):
        Property.init_storage(self, obj, storage)
        storage.bnum_min = self.min
        storage.bnum_max = self.max
        storage.bnum_f_min = self.f_min
        storage.bnum_f_max = self.f_max
        storage.bnum_use_min = self.use_min
        storage.bnum_use_max = self.use_max

    def set_min(self, EventDispatcher obj, value):
        '''Change the minimum value acceptable for the BoundedNumericProperty,
        only for the `obj` instance. Set to None if you want to disable it::

            class MyWidget(Widget):
                number = BoundedNumericProperty(0, min=-5, max=5)

            widget = MyWidget()
            # change the minmium to -10
            widget.property('number').set_min(widget, -10)
            # or disable the minimum check
            widget.property('number').set_min(widget, None)

        .. warning::

            Changing the bounds doesn't revalidate the current value.

        .. versionadded:: 1.1.0
        '''
        cdef PropertyStorage ps = obj.__storage[self._name]
        if value is None:
            ps.bnum_use_min = 0
        elif type(value) is float:
            ps.bnum_f_min = value
            ps.bnum_use_min = 2
        else:
            ps.bnum_min = value
            ps.bnum_use_min = 1

    def get_min(self, EventDispatcher obj):
        '''Return the minimum value acceptable for the BoundedNumericProperty
        in `obj`. Return None if no minimum value is set::

            class MyWidget(Widget):
                number = BoundedNumericProperty(0, min=-5, max=5)

            widget = MyWidget()
            print(widget.property('number').get_min(widget))
            # will output -5

        .. versionadded:: 1.1.0
        '''
        cdef PropertyStorage ps = obj.__storage[self._name]
        if ps.bnum_use_min == 1:
            return ps.bnum_min
        elif ps.bnum_use_min == 2:
            return ps.bnum_f_min

    def set_max(self, EventDispatcher obj, value):
        '''Change the maximum value acceptable for the BoundedNumericProperty,
        only for the `obj` instance. Set to None if you want to disable it.
        Check :data:`set_min` for a usage example.

        .. warning::

            Changing the bounds doesn't revalidate the current value.

        .. versionadded:: 1.1.0
        '''
        cdef PropertyStorage ps = obj.__storage[self._name]
        if value is None:
            ps.bnum_use_max = 0
        elif type(value) is float:
            ps.bnum_f_max = value
            ps.bnum_use_max = 2
        else:
            ps.bnum_max = value
            ps.bnum_use_max = 1

    def get_max(self, EventDispatcher obj):
        '''Return the maximum value acceptable for the BoundedNumericProperty
        in `obj`. Return None if no maximum value is set. Check
        :data:`get_min` for a usage example.

        .. versionadded:: 1.1.0
        '''
        cdef PropertyStorage ps = obj.__storage[self._name]
        if ps.bnum_use_max == 1:
            return ps.bnum_max
        if ps.bnum_use_max == 2:
            return ps.bnum_f_max

    cdef check(self, EventDispatcher obj, value):
        if Property.check(self, obj, value):
            return True
        cdef PropertyStorage ps = obj.__storage[self._name]
        if ps.bnum_use_min == 1:
            _min = ps.bnum_min
            if value < _min:
                raise ValueError('%s.%s is below the minimum bound (%d)' % (
                    obj.__class__.__name__,
                    self.name, _min))
        elif ps.bnum_use_min == 2:
            _f_min = ps.bnum_f_min
            if value < _f_min:
                raise ValueError('%s.%s is below the minimum bound (%f)' % (
                    obj.__class__.__name__,
                    self.name, _f_min))
        if ps.bnum_use_max == 1:
            _max = ps.bnum_max
            if value > _max:
                raise ValueError('%s.%s is above the maximum bound (%d)' % (
                    obj.__class__.__name__,
                    self.name, _max))
        elif ps.bnum_use_max == 2:
            _f_max = ps.bnum_f_max
            if value > _f_max:
                raise ValueError('%s.%s is above the maximum bound (%f)' % (
                    obj.__class__.__name__,
                    self.name, _f_max))
        return True

    property bounds:
        '''Return min/max of the value.

        .. versionadded:: 1.0.9
        '''

        def __get__(self):
            if self.use_min == 1:
                _min = self.min
            elif self.use_min == 2:
                _min = self.f_min
            else:
                _min = None

            if self.use_max == 1:
                _max = self.max
            elif self.use_max == 2:
                _max = self.f_max
            else:
                _max = None

            return _min, _max


cdef class OptionProperty(Property):
    '''Property that represents a string from a predefined list of valid
    options.

    If the string set in the property is not in the list of valid options
    (passed at property creation time), a ValueError exception will be raised.

    :Parameters:
        `options`: list (not tuple.)
            List of valid options
    '''
    def __cinit__(self):
        self.options = []

    def __init__(self, *largs, **kw):
        self.options = list(kw.get('options', []))
        super(OptionProperty, self).__init__(*largs, **kw)

    cdef init_storage(self, EventDispatcher obj, PropertyStorage storage):
        Property.init_storage(self, obj, storage)
        storage.options = self.options[:]

    cdef check(self, EventDispatcher obj, value):
        if Property.check(self, obj, value):
            return True
        cdef PropertyStorage ps = obj.__storage[self._name]
        if value not in ps.options:
            raise ValueError('%s.%s is set to an invalid option %r. '
                             'Must be one of: %s' % (
                             obj.__class__.__name__,
                             self.name,
                             value, ps.options))

    property options:
        '''Return the options available.

        .. versionadded:: 1.0.9
        '''

        def __get__(self):
            return self.options

class ObservableReferenceList(ObservableList):
    def __setitem__(self, key, value, update_properties=True):
        list.__setitem__(self, key, value)
        if update_properties:
            self.prop.setitem(self.obj(), key, value)

    def __setslice__(self, start, stop, value, update_properties=True):  # Python 2 only method
        list.__setslice__(self, start, stop, value)
        if update_properties:
            self.prop.setitem(self.obj(), slice(start, stop), value)

cdef class ReferenceListProperty(Property):
    '''Property that allows the creaton of a tuple of other properties.

    For example, if `x` and `y` are :class:`NumericProperty`s, we can create a
    :class:`ReferenceListProperty` for the `pos`. If you change the value of
    `pos`, it will automatically change the values of `x` and `y` accordingly.
    If you read the value of `pos`, it will return a tuple with the values of
    `x` and `y`.
    '''
    def __cinit__(self):
        self.properties = list()

    def __init__(self, *largs, **kw):
        for prop in largs:
            self.properties.append(prop)
        Property.__init__(self, largs, **kw)

    cdef init_storage(self, EventDispatcher obj, PropertyStorage storage):
        Property.init_storage(self, obj, storage)
        storage.properties = tuple(self.properties)
        storage.stop_event = 0

    cpdef link(self, EventDispatcher obj, str name):
        Property.link(self, obj, name)
        cdef PropertyStorage ps = obj.__storage[self._name]
        ps.value = ObservableReferenceList(self, obj, ps.value)

    cpdef link_deps(self, EventDispatcher obj, str name):
        cdef Property prop
        Property.link_deps(self, obj, name)
        for prop in self.properties:
            prop.bind(obj, self.trigger_change)

    cpdef trigger_change(self, EventDispatcher obj, value):
        cdef PropertyStorage ps = obj.__storage[self._name]
        if ps.stop_event:
            return
        p = ps.properties

        try:
            ps.value.__setslice__(0, len(p),
                    [prop.get(obj) for prop in p],
                    update_properties=False)
        except AttributeError:
            ps.value.__setitem__(slice(len(p)),
                    [prop.get(obj) for prop in p],
                    update_properties=False)

        self.dispatch(obj)

    cdef convert(self, EventDispatcher obj, value):
        if not isinstance(value, (list, tuple)):
            raise ValueError('%s.%s must be a list or a tuple' % (
                obj.__class__.__name__,
                self.name))
        return list(value)

    cdef check(self, EventDispatcher obj, value):
        cdef PropertyStorage ps = obj.__storage[self._name]
        if len(value) != len(ps.properties):
            raise ValueError('%s.%s value length is immutable' % (
                obj.__class__.__name__,
                self.name))

    cpdef set(self, EventDispatcher obj, _value):
        cdef int idx
        cdef list value
        cdef PropertyStorage ps = obj.__storage[self._name]
        value = self.convert(obj, _value)
        if self.compare_value(ps.value, value):
            return False
        self.check(obj, value)
        # prevent dependency loop
        ps.stop_event = 1
        props = ps.properties
        for idx in xrange(len(props)):
            prop = props[idx]
            x = value[idx]
            prop.set(obj, x)
        ps.stop_event = 0
        try:
            ps.value.__setslice__(0, len(value), value,
                    update_properties=False)
        except AttributeError:
            ps.value.__setitem__(slice(len(value)), value,
                    update_properties=False)
        self.dispatch(obj)
        return True

    cpdef setitem(self, EventDispatcher obj, key, value):
        cdef PropertyStorage ps = obj.__storage[self._name]

        ps.stop_event = 1
        if isinstance(key, slice):
            props = ps.properties[key]
            for index in xrange(len(props)):
                prop = props[index]
                x = value[index]
                prop.set(obj, x)
        else:
            prop = ps.properties[key]
            prop.set(obj, value)
        ps.stop_event = 0
        self.dispatch(obj)

    cpdef get(self, EventDispatcher obj):
        cdef PropertyStorage ps = obj.__storage[self._name]
        cdef tuple p = ps.properties
        try:
            ps.value.__setslice__(0, len(p),
                    [prop.get(obj) for prop in p],
                    update_properties=False)
        except AttributeError:
            ps.value.__setitem__(slice(len(p)),
                    [prop.get(obj) for prop in p],
                    update_properties=False)
        return ps.value

cdef class AliasProperty(Property):
    '''Create a property with a custom getter and setter.

    If you don't find a Property class that fits to your needs, you can make
    your own by creating custom Python getter and setter methods.

    Example from kivy/uix/widget.py::

        def get_right(self):
            return self.x + self.width
        def set_right(self, value):
            self.x = value - self.width
        right = AliasProperty(get_right, set_right, bind=('x', 'width'))

    :Parameters:
        `getter`: function
            Function to use as a property getter
        `setter`: function
            Function to use as a property setter
        `bind`: list/tuple
            Properties to observe for changes, as property name strings
        `cache`: boolean
            If True, the value will be cached, until one of the binded elements
            will changes

    .. versionchanged:: 1.4.0
        Parameter `cache` added.
    '''
    def __cinit__(self):
        self.getter = None
        self.setter = None
        self.use_cache = 0
        self.bind_objects = list()

    def __init__(self, getter, setter, **kwargs):
        Property.__init__(self, None, **kwargs)
        self.getter = getter
        self.setter = setter
        v = kwargs.get('bind')
        self.bind_objects = list(v) if v is not None else []
        self.use_cache = 1 if kwargs.get('cache') else 0

    cdef init_storage(self, EventDispatcher obj, PropertyStorage storage):
        Property.init_storage(self, obj, storage)
        storage.getter = self.getter
        storage.setter = self.setter
        storage.alias_initial = 1

    cpdef link_deps(self, EventDispatcher obj, str name):
        cdef Property oprop
        for prop in self.bind_objects:
            oprop = getattr(obj.__class__, prop)
            oprop.bind(obj, self.trigger_change)

    cpdef trigger_change(self, EventDispatcher obj, value):
        cdef PropertyStorage ps = obj.__storage[self._name]
        ps.alias_initial = 1
        dvalue = self.get(obj)
        if ps.value != dvalue:
            ps.value = dvalue
            self.dispatch(obj)

    cdef check(self, EventDispatcher obj, value):
        return True

    cpdef get(self, EventDispatcher obj):
        cdef PropertyStorage ps = obj.__storage[self._name]
        if self.use_cache:
            if ps.alias_initial:
                ps.value = ps.getter(obj)
                ps.alias_initial = 0
            return ps.value
        return ps.getter(obj)

    cpdef set(self, EventDispatcher obj, value):
        cdef PropertyStorage ps = obj.__storage[self._name]
        if ps.setter(obj, value):
            ps.value = self.get(obj)
            self.dispatch(obj)

cdef class VariableListProperty(Property):
    '''A ListProperty that mimics the css way of defining numeric values such
    as padding, margin, etc.

    Accepts a list of 1 or 2 (or 4 when length=4) Numeric arguments or a single
    Numeric argument.

    - VariableListProperty([1]) represents [1, 1, 1, 1].
    - VariableListProperty([1, 2]) represents [1, 2, 1, 2].
    - VariableListProperty(['1px', (2, 'px'), 3, 4.0]) represents [1, 2, 3, 4.0].
    - VariableListProperty(5) represents [5, 5, 5, 5].
    - VariableListProperty(3, length=2) represents [3, 3].

    :Parameters:
        `length`: int
            The length of the list, can be 2 or 4.

    .. versionadded:: 1.7.0
    '''

    def __init__(self, defaultvalue=None, length=4, **kw):
        if length == 4:
            defaultvalue = defaultvalue or [0, 0, 0, 0]
        elif length == 2:
            defaultvalue = defaultvalue or [0, 0]
        else:
            err = 'VariableListProperty requires a length of 2 or 4 (got %r)'
            raise ValueError(err % length)

        self.length = length
        super(VariableListProperty, self).__init__(defaultvalue, **kw)

    cpdef link(self, EventDispatcher obj, str name):
        Property.link(self, obj, name)
        cdef PropertyStorage ps = obj.__storage[self._name]
        ps.value = ObservableList(self, obj, ps.value)

    cdef check(self, EventDispatcher obj, value):
        if Property.check(self, obj, value):
            return True
        if type(value) not in (int, float, long, list, tuple, str):
            err = '%s.%s accepts only int/float/long/list/tuple/str (got %r)'
            raise ValueError(err % (obj.__class__.__name__, self.name, value))

    cdef convert(self, EventDispatcher obj, x):
        if x is None:
            return x

        tp = type(x)
        if tp is list or tp is tuple:
            l = len(x)
            if l == 1:
                y = self._convert_numeric(obj, x[0])
                if self.length == 4:
                    return [y, y, y, y]
                elif self.length == 2:
                    return [y, y]
            elif l == 2:
                if x[1] in NUMERIC_FORMATS:
                    # defaultvalue is a list or tuple representing one value
                    y = self._convert_numeric(obj, x)
                    if self.length == 4:
                        return [y, y, y, y]
                    elif self.length == 2:
                        return [y, y]
                else:
                    y = self._convert_numeric(obj, x[0])
                    z = self._convert_numeric(obj, x[1])
                    if self.length == 4:
                        return [y, z, y, z]
                    elif self.length == 2:
                        return [y, z]
            elif l == 4:
                if self.length == 4:
                    return [self._convert_numeric(obj, y) for y in x]
                else:
                    err = '%s.%s must have 1 or 2 components (got %r)'
                    raise ValueError(err % (obj.__class__.__name__,
                        self.name, x))
            else:
                if self.length == 4:
                    err = '%s.%s must have 1, 2 or 4 components (got %r)'
                elif self.length == 2:
                    err = '%s.%s must have 1 or 2 components (got %r)'
                raise ValueError(err % (obj.__class__.__name__, self.name, x))
        elif tp is int or tp is long or tp is float or tp is str:
            y = self._convert_numeric(obj, x)
            if self.length == 4:
                return [y, y, y, y]
            elif self.length == 2:
                return [y, y]
        else:
            raise ValueError('%s.%s has an invalid format (got %r)' % (
                obj.__class__.__name__,
                self.name, x))

    cdef _convert_numeric(self, EventDispatcher obj, x):
        tp = type(x)
        if tp is int or tp is float or tp is long:
            return x
        if tp is tuple or tp is list:
            if len(x) != 2:
                raise ValueError('%s.%s must have 2 components (got %r)' % (
                    obj.__class__.__name__,
                    self.name, x))
            return self.parse_list(obj, x[0], <str>x[1])
        elif tp is str:
            return self.parse_str(obj, x)
        else:
            raise ValueError('%s.%s have an invalid format (got %r)' % (
                obj.__class__.__name__,
                self.name, x))

    cdef float parse_str(self, EventDispatcher obj, value):
        return self.parse_list(obj, value[:-2], <str>value[-2:])

    cdef float parse_list(self, EventDispatcher obj, value, str ext):
        return dpi2px(value, ext)


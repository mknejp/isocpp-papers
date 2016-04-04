=======================================
 allocate_unique and related utilities
=======================================

:Document:	Dxxxx
:Date:		2016-04-04
:Project:	Programming Language C++
:Audience:	Library Evolution Working Group
:Author:	Miro Knejp <miro.knejp@gmail.com>
:URL:		https://github.com/mknejp/isocpp-papers/blob/master/dxxxx-allocate_unique.rst

Abstract
========

This paper proposes the addition of the function ``allocate_unique()`` to complement the functionality of ``allocate_shared()`` for ``unique_ptr``, as well as the addition of the utilities ``allocator_delete`` and ``make_allocator_delete()`` to hide frequently needed boilerplate when implementing allocator-aware data structures.

.. contents::

Motivation
==========

There is currently an asymmetry in functionality regarding the creation of ``shared_ptr`` and ``unique_ptr``. Both of them can be conviently created with ``make_shared()`` and ``make_unique()``, respectively, using the default allocator. However if one wishes to use a custom allocator only the former provides a convenient factory in the form of ``allocate_shared()`` whereas there is no such facility for ``unique_ptr`` and one has to write quite an amount of non-trivial code to create one's own.

The additions proposed in this paper can be found re-intenved in virtually every library that offers custom allocator support and are already present in standard library implementations for internal use making it obvious this is a frequently sought after functionality that should be readily available in the standard (and *de-facto* already is, albeit not under a well-known name).

The inclusion of ``allocator_delete`` and ``make_allocator_delete()`` removes an additional burden for implementing allocator-aware data structures outside the scope of ``unique_ptr``. Together with ``allocate_unique`` they provide the means to conveniently create and destroy objects with custom allocators which are not directly tied to ``unique_ptr`` lifetimes (such as node-based or type-erasing containers, to name a few).

Proposal
========

Synopsis
--------

.. code:: c++

	template<class T, class Alloc>
	class allocator_delete {
	public:
	  using allocator_type = remove_cv_t<Alloc>;
	  using pointer = typename allocator_traits<allocator_type>::pointer;

	  template<class... Args>
	  allocator_delete(Args&&... args);

	  void operator()(pointer p);

	  allocator_type& get_allocator();
	  const allocator_type& get_allocator() const;

	private:
	  allocator_type alloc; // for exposition only
	};

	template<class T, class Alloc>
	class allocator_delete<T, Alloc&> {
	public:
	  using allocator_type = remove_cv_t<Alloc>;
	  using pointer = typename allocator_traits<allocator_type>::pointer;

	  allocator_delete(Alloc& alloc);
	  allocator_delete(reference_wrapper<Alloc> alloc);

	  void operator()(pointer p);

	  Alloc& get_allocator() const;

	private:
	  reference_wrapper<Alloc> alloc; // for exposition only
	};

	template<class T, class Alloc>
	  allocator_delete<T, typename allocator_traits<decay_t<Alloc>>::template rebind_alloc<T>>
	    make_allocator_delete(Alloc&& alloc);

	template<class T, class Alloc>
	  allocator_delete<T, Alloc&>
	    make_allocator_delete(reference_wrapper<Alloc> alloc);

	template<class T, class Alloc, class... Args>
	  unique_ptr<T, allocator_delete<T, typename allocator_traits<remove_cv_t<Alloc>>::template rebind_alloc<T>>>
	    allocate_unique(const Alloc& alloc, Args&&... args);

	template<class T, class Alloc, class... Args>
	  unique_ptr<T, allocator_delete<T, Alloc&>>
	    allocate_unique(reference_wrapper<Alloc> alloc, Args&&... args);

allocator_delete
----------------

The standard library already provides one type intended to be used as the ``Deleter`` for ``unique_ptr``, namely ``default_delete``. The proposed ``allocator_delete`` is a second standard-provided deleter which does not use the ``delete`` operator but instead delegates destruction and deletion to a user-provided allocator. By default it stores a copy of the allocator and delegates the necessary operations to the stored copy. A partial specialization for allocator references is provided which only stores a reference to the actual allocator instead of a copy for cases where allocators are stateful and either too big to be carried around in every ``unique_ptr`` instance or expensive to copy.

``allocator_delete`` does not perform rebinding in its call operator. It is an error to instantiate ``allocator_delete`` with a type ``Alloc`` not capable of deallocating objects of type ``T``. This decision was deliberately made to avoid unnecessary rebinding and copy-constructing of potentially stateful allocators for every single deletion in the call operator.

make_allocator_delete
---------------------

Because ``allocator_delete`` must be instantiated only with an allocator type capable of deallocating the intended target type it cannot be naively created from an existing allocator without doing additional work. ``make_allocator_delete()`` is the utility that hides this rebinding business from users and always returns an ``allocator_delete`` type with an allocator capable of deallocating objects of type ``T``.

The overload taking a ``reference_wrapper<Alloc>`` results in an ``allocator_delete`` storing only a reference to an allocator instead of a copy. Because the type of the existing allocator cannot be changed and because it would be surprising to create a copy of the allocator when the user *deliberately* specified a ``reference_wrapper``, the referenced allocator must have the same type as the rebound allocator for type ``T``, meaning the condition ``is_same<remove_cv<Alloc>, allocator_traits<remove_cv<Alloc>>::rebind_alloc<T>>::value`` must be ``true``.

allocate_unique
---------------

This is the main motivation of this proposal. The above are required to implement ``allocate_unique()`` but are useful enough on their own outside the scope of ``allocate_unique()`` and are therefore proposed as well.

The ``allocate_unique()`` function is not overly big but tricky enough to implement that a naive approach might be incorrect. Below is an implementation that, to the author's knowledge, is correct and exception safe. Achieving exception safety with the two-phase creation required with the allocator interface is a common oversight.

.. code:: c++

	template<class T, class Alloc, class... Args>
	auto allocate_unique(const Alloc& alloc, Args&&... args) {
	  using traits = typename allocator_traits<Alloc>::template rebind_traits<T>;
	  auto hold_deleter = [&alloc] (auto p) {
	    traits::deallocate(alloc, p, 1);
	  };
	  auto deleter = make_allocator_delete<T>(alloc);
	  unique_ptr<T, decltype(hold_deleter)> hold(traits::allocate(alloc, 1), hold_deleter);
	  traits::construct(alloc, hold.get(), forward<Args>(args)...);
	  return unique_ptr<T, decltype(deleter)>{hold.release(), move(deleter)};
	}

Implementations very similar to the above can be found in numerous libraries and standard implementations. It is a pattern of boilerplate that is repeated frequently enough that it should be included in the standard. Often the intermediary use of a RAII wrapper around the ``allocate``-``deallocate`` pair is forgotten thus resulting in memory leaks if the constructor of ``T`` throws. This is a trap people should not have to worry about in the first place.

Applications Outside of allocate_shared
=======================================

``allocator_delete`` and ``make_allocator_delete()`` are technically not required to be made available in the standard library's public interface as they can be easily marked as *implementation-defined* in the return type of ``allocate_shared()`` as is currently done for the return type of ``bind()``. However their utility shows itself even in other applications for which some examples are given here to convince the reader of their usefulness.

Node-Based Containers
---------------------

Node-based containers like ``map`` or ``list`` do typically not store a ``unique_ptr`` referencing each and every node. That would store ``n`` copies of the deleter which would each have to either copy the allocator for every node or store a reference to the allocator to utilize automatic cleanup. Both are unnecessarily wasteful. The latter establishes a *back reference* from the node to the container, meaning the container becomes expensive to move as all the back references have to be updated. Instead these containers typically manually allocate/deallocate each node, store them as raw pointers, and because the type of a node is virtually never the same type as the payload, rebinding the allocator for the node type is necessary as well. Then for actually allocating each node a procedure similar to the above is performed, followed later by the manual deletion.

This means in practice something like this:

.. code:: c++
	
	template<class T, class Alloc>
	class list {
	  struct node {
	    node* next;
	    T payload;
	    ...
	  }
	  using node_allocator = typename allocator_traits<Alloc>::template rebind_alloc<node>;
	  using traits = allocator_traits<node_allocator>;
	  node_allocator alloc;

	  ...

	public:
	  void push_back(T x) {
	    auto hold_deleter = [&alloc] (auto p) {
	      traits::deallocate(alloc, p, 1);
	    };
	    unique_ptr<node, decltype(hold_deleter)> hold(traits::allocate(alloc, 1), hold_deleter);
	    traits::construct(alloc, hold.get(), ...);
	    append_node_to_list(hold.release()); // noexcept
	  }

	  ~list() {
	    for(auto* node : nodes()) {
	      traits::destroy(alloc, node);
	      traits::deallocate(alloc, node, 1);
	    }
	  }
	};

Compare this to using the utilities proposed in this paper:

.. code:: c++

	template<class T, class Alloc>
	class list {
	  struct node {
	    node* next;
	    T payload;
	    ...
	  }
	  using node_allocator = typename allocator_traits<Alloc>::template rebind_alloc<node>;
	  node_allocator alloc;

	  ...

	public:
	  void push_back(T x) {
	    auto p = allocate_unique<node>(ref(alloc), ...);
	    append_node_to_list(p.release()); // noexcept
	  }

	  ~list() {
	    auto del = make_allocator_deleter<node>(ref(alloc));
	    for(auto* node : nodes()) {
	      del(node);
	    }
	  }
	};

It may not seem like much but the parts that were replaced in the second snippet were the most error-prone. It has much less fiddling around with ``allocator_traits`` and one did not have to bother themselves with the nature of two-phase initialization and teardown of objects imposed by the allocator interface.

Type Erasure
------------

Containers like ``function`` or ``shared_ptr`` employ a technique called *type erasure* where the exact type of the stored object is not visible in the container's type signature. Implementations often rely on using an internal abstract base class from which concrete class templates are derived. If the container has support for user-provided allocators then the allocator has to be stored somewhere as well. But because the type of the allocator is not part of the container's type signature it, too, must be erased. This means both the payload *and* the actual allocator are part of the internal object, often simply combined into a ``tuple<Alloc, T>``.

Below is an excerpt showing how such type erasure is frequently implemented:

.. code:: c++

	class any {
	  struct base {
	    virtual void destroy() noexcept = 0;
	    virtual void do_something() = 0;
	  protected:
	    ~base() = default;
	  }

	  template<class Alloc, class T>
	  struct derived : base {
	    derived(const Alloc& alloc, T x);
	    void destroy() noexcept override {
	      using rebind = typename allocator_traits<Alloc>::template rebind_alloc<derived>; // X
	      rebind alloc{move(get<0>(data))};                                                // X
	      auto* p = this;                                                                  // X <- danger
	      allocator_traits<rebind>::destroy(alloc, p);                                     // X
	      allocator_traits<rebind>::deallocate(alloc, p, 1);                               // X
	    }
	    void do_something() override { ... }
	    tuple<Alloc, T> data;
	  };

	  base* value;

	public:
	  ...

	  template<class Alloc, class T>
	  void assign(const Alloc& alloc, T x) {
	    using node = derived<Alloc, T>;
	    using rebind = typename allocator_traits<Alloc>::template rebind_alloc<node>;                 // X
	    using traits = allocator_traits<rebind>;                                                      // X
	    auto node_alloc = rebind{alloc};                                                              // X
	    auto hold_deleter = [&node_alloc] (auto p) {                                                  // X
	      traits::deallocate(node_alloc, p, 1);                                                       // X
	    };                                                                                            // X
	    unique_ptr<node, decltype(hold_deleter)> hold(traits::allocate(node_alloc, 1), hold_deleter); // X
	    traits::construct(node_alloc, hold.get(), alloc, move(x));                                    // X
	    if(value) {
	      value->destroy();
	    }
	    value = hold.release();
	  }
	  ~any {
	    if(value) {
	      value->destroy();
	    }
	  }
	};

About half the functional code in this example (marked with ``X``) deals with nothing else but rebinding allocators and doing the allocator dance. It also contains subtle traps. Note the line marked with **danger**. Were one to not make a copy of ``this`` but pass it as argument to ``destroy()`` and ``deallocate()`` then accessing ``this`` after the call to ``destroy()`` (which calls the destructor) is undefined. The above can be significantly simplified with the proper tools:

.. code:: c++

	class any {
	  struct base {
	    virtual void destroy() noexcept = 0;
	    virtual void do_something() = 0;
	  protected:
	    ~base() = default;
	  }

	  template<class Alloc, class T>
	  struct derived : base {
	    derived(const Alloc& alloc, T x);
	    void destroy() noexcept override {
	      auto deleter = make_allocator_delete<derived>(move(get<0>(data))); // X
	      deleter(this);                                                     // X
	    }
	    void do_something() override { ... }
	    tuple<Alloc, T> data;
	  };

	  base* value;

	public:
	  ...

	  template<class Alloc, class T>
	  void assign(const Alloc& alloc, T x) {
	    using node = derived<Alloc, T>;
	    auto p = allocate_unique<node>(alloc, alloc, x); // X
	    if(value) {
	      value->destroy();
	    }
	    value = p.release();
	  }
	  ~any {
	    if(value) {
	      value->destroy();
	    }
	  }
	};

In the altered example only *three lines of code* (marked with ``X``) deal with creation and destuction of the type erased objects with a custom allocator. Note that we pass the allocator twice to ``allocate_unique()`` as the first argument is the allocator used to allocate the node (automatically rebound for us to the compatible type) and the second argument is forwarded to the allocated node to make a copy available for the ``destroy()`` method.

Open Issues
===========

allocate_unique<T[]>
--------------------

The current design of ``unique_ptr`` and the associated deleter means we cannot make ``allocator_delete`` compatible with the array-based ``unique_ptr<T[]>`` specialization because there is no way to tell the deleter how many objects to delete. ``default_delete`` circumvents this problem because the ``delete[]`` operator knows how many elements were allocated with ``new T[]`` and it combines both destruction and deallocation in one operation. In contrast the allocator interface imposes a two-phase cleanup process. Making ``allocator_delete`` universally compatible with array-based ``unique_ptr<T[]>`` requires the addition of a second overload to the deleter's call operator with the signature ``void(pointer p, size_t n)`` which ``unique_ptr<T[]>`` would prefer if present. This overload loops over all elements calling ``destroy()`` for each and finally calls ``deallocate()`` with the provided size.

But since that requires modifications to existing library types it is currently not proposed and therefore ``allocate_unique()`` with its first template parameter being of the form ``T[]`` is ill-formed.

Summary
=======

Experience shows that the mechanism abstracted behind ``allocate_unique()`` is widely re-invented in many projects. Standard library implementations already have it for internal use but people still have to implement their own. As shown in this proposal doing so correctly is tricky and requires more knowledge about the interface of allocators than is usually necessary to actually do the required job. As such the barrier of entry to providing allocator support in a library is often very high as doing it properly involves careful studying of the allocator interface which many consider to be expert-level territory and prefer not to touch with a ten foot pole.

The provided examples show how making some utilities used to implement ``allocate_unique()`` available as part of the public interface can greatly help in adding allocator support to other data structures by significantly cutting down on the required boilerplate.

Technical Specification
=======================

TBA

References
==========

TBA

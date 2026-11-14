"""androidx.recyclerview.widget: a list that is an adapter, view holders and a linear layout manager over the scroll view of the app

the android list recycles the few views that are on screen. here every item gets a view of its own, in a column (or a row) inside the scroll
view, so a list is at most MAX_ITEMS long and a longer one is an IllegalStateException that says so. views of items that were taken out are
kept per view type and bound again for the next ones, which is the part of recycling that matters to a plugin: onCreateViewHolder runs once
for a view and onBindViewHolder for each time it shows an item. the scroll position belongs to the app, so a plugin cannot move it or
listen to it"""

from android.view import MATCH_PARENT, WRAP_CONTENT, MarginLayoutParams
from android.widget import HorizontalScrollView, LinearLayout, ScrollView
from java.lang import IllegalArgumentException, IllegalStateException, Object, UnsupportedOperationException


class RecyclerView(ScrollView):
    MAX_ITEMS = 1000
    NO_POSITION = -1
    NO_ID = -1
    VERTICAL = 1
    HORIZONTAL = 0

    class ViewHolder(Object):
        def __init__(self, item_view):
            if item_view is None:
                raise IllegalArgumentException("itemView may not be null")
            self.itemView = item_view
            self._position = RecyclerView.NO_POSITION
            self._type = 0
            self._id = RecyclerView.NO_ID

        def getAdapterPosition(self):
            return self._position

        getBindingAdapterPosition = getLayoutPosition = getAbsoluteAdapterPosition = getOldPosition = getAdapterPosition

        def getItemViewType(self):
            return self._type

        def getItemId(self):
            return self._id

    class Adapter(Object):
        """a program implements getItemCount(), onCreateViewHolder(parent, view_type) and onBindViewHolder(holder, position)"""

        def __init__(self):
            self._lists = []
            self._stable = False

        def getItemCount(self):
            raise NotImplementedError("an adapter answers getItemCount")

        def onCreateViewHolder(self, parent, view_type):
            raise NotImplementedError("an adapter answers onCreateViewHolder")

        def onBindViewHolder(self, holder, position, *_payloads):
            raise NotImplementedError("an adapter answers onBindViewHolder")

        def getItemViewType(self, position):
            return 0

        def getItemId(self, position):
            return RecyclerView.NO_ID

        def setHasStableIds(self, value):
            self._stable = bool(value)

        def hasStableIds(self):
            return self._stable

        def _attach(self, lst):
            if lst not in self._lists:
                self._lists.append(lst)

        def _detach(self, lst):
            if lst in self._lists:
                self._lists.remove(lst)

        def notifyDataSetChanged(self):
            for lst in list(self._lists):
                lst._rebuild()

        notifyItemInserted = notifyItemRemoved = notifyItemRangeInserted = notifyItemRangeRemoved = lambda self, *args: self.notifyDataSetChanged()
        notifyItemMoved = lambda self, *args: self.notifyDataSetChanged()

        def notifyItemChanged(self, position, *payload):
            for lst in list(self._lists):
                lst._rebind(int(position), 1, payload[0] if payload else None)

        def notifyItemRangeChanged(self, start, count, *payload):
            for lst in list(self._lists):
                lst._rebind(int(start), int(count), payload[0] if payload else None)

    class LayoutManager(Object):
        pass

    class ItemAnimator(Object):
        """the items change without an animation; the settings are kept for a plugin that reads them back"""

        def __init__(self):
            self._supports_change = True
            self._durations = {}

        def setSupportsChangeAnimations(self, value):
            self._supports_change = bool(value)

        def getSupportsChangeAnimations(self):
            return self._supports_change

        def _set(self, name, value):
            self._durations[name] = int(value)

        def setAddDuration(self, value):
            self._set("add", value)

        def setRemoveDuration(self, value):
            self._set("remove", value)

        def setMoveDuration(self, value):
            self._set("move", value)

        def setChangeDuration(self, value):
            self._set("change", value)

        def getAddDuration(self):
            return self._durations.get("add", 120)

        def getRemoveDuration(self):
            return self._durations.get("remove", 120)

        def getMoveDuration(self):
            return self._durations.get("move", 250)

        def getChangeDuration(self):
            return self._durations.get("change", 250)

    def __init__(self, context=None, *args):
        super().__init__(context, *args)
        self._adapter = None
        self._manager = None
        self._animator = None
        self._column = LinearLayout(context)
        self._column.setOrientation(LinearLayout.VERTICAL)
        self.addView(self._column, ScrollView._default_params(self))
        self._holders = []
        self._pool = {}

    def _horizontal(self):
        return self._manager is not None and self._manager.getOrientation() == RecyclerView.HORIZONTAL

    def _on_measure(self, wspec, hspec):
        if self._horizontal():
            return HorizontalScrollView._on_measure(self, wspec, hspec)
        return ScrollView._on_measure(self, wspec, hspec)

    def setLayoutManager(self, manager):
        self._manager = manager
        self._column.setOrientation(LinearLayout.HORIZONTAL if self._horizontal() else LinearLayout.VERTICAL)
        self._rebuild()
        self._request_layout()

    def getLayoutManager(self):
        return self._manager

    def setAdapter(self, adapter):
        if self._adapter is not None:
            self._adapter._detach(self)
        self._adapter = adapter
        self._pool = {}
        self._holders = []
        self._column.removeAllViews()
        if adapter is not None:
            adapter._attach(self)
        self._rebuild()

    def getAdapter(self):
        return self._adapter

    def setItemAnimator(self, animator):
        self._animator = animator

    def getItemAnimator(self):
        return self._animator

    def setHasFixedSize(self, value):
        return None

    def setClipToPadding(self, value):
        return None

    def setOverScrollMode(self, mode):
        return None

    def addOnScrollListener(self, listener):
        raise UnsupportedOperationException("the scroll position belongs to the app, no scroll event reaches python")

    setOnScrollListener = scrollToPosition = smoothScrollToPosition = addOnScrollListener

    def _params_for(self, view):
        """the layout params the layout manager gives an item that has none: the full width and its own height in a column, the reverse in a row"""
        horizontal = self._horizontal()
        old = view.getLayoutParams()
        params = LinearLayout.LayoutParams(old.width if old is not None else (WRAP_CONTENT if horizontal else MATCH_PARENT),
                                           old.height if old is not None else (MATCH_PARENT if horizontal else WRAP_CONTENT))
        if isinstance(old, MarginLayoutParams):
            params.setMargins(old.leftMargin, old.topMargin, old.rightMargin, old.bottomMargin)
        return params

    def _rebuild(self):
        if self._adapter is None:
            return
        count = int(self._adapter.getItemCount())
        if count > RecyclerView.MAX_ITEMS:
            raise IllegalStateException("a list of %d items needs the recycling of android, this one keeps a view for each item and takes at most %d"
                                        % (count, RecyclerView.MAX_ITEMS))
        for holder in self._holders:
            self._pool.setdefault(holder._type, []).append(holder)
        self._holders = []
        self._column.removeAllViews()
        reverse = self._manager is not None and self._manager.getReverseLayout()
        for position in range(count):
            self._holders.append(self._bound(position))
        for holder in (reversed(self._holders) if reverse else self._holders):
            self._column.addView(holder.itemView, self._params_for(holder.itemView))
        self._pool = {kind: kept for kind, kept in self._pool.items() if kept}

    def _bound(self, position, payload=None):
        adapter = self._adapter
        view_type = adapter.getItemViewType(position)
        kept = self._pool.get(view_type)
        holder = kept.pop() if kept else adapter.onCreateViewHolder(self, view_type)
        if not isinstance(holder, RecyclerView.ViewHolder):
            raise IllegalStateException("onCreateViewHolder gave %r, not a ViewHolder" % (holder,))
        holder._position, holder._type, holder._id = position, view_type, adapter.getItemId(position)
        adapter.onBindViewHolder(holder, position)
        return holder

    def _rebind(self, start, count, payload):
        if self._adapter is None or start < 0 or start + count > len(self._holders):
            from java.lang import IndexOutOfBoundsException
            raise IndexOutOfBoundsException("item %d..%d of a list of %d" % (start, start + count - 1, len(self._holders)))
        for position in range(start, start + count):
            holder = self._holders[position]
            self._adapter.onBindViewHolder(holder, position)

    def findViewHolderForAdapterPosition(self, position):
        return self._holders[position] if 0 <= position < len(self._holders) else None

    findViewHolderForLayoutPosition = findViewHolderForAdapterPosition

    def getChildAdapterPosition(self, child):
        for holder in self._holders:
            if holder.itemView is child:
                return holder._position
        return RecyclerView.NO_POSITION

    getChildLayoutPosition = getChildAdapterPosition


class LinearLayoutManager(RecyclerView.LayoutManager):
    HORIZONTAL = RecyclerView.HORIZONTAL
    VERTICAL = RecyclerView.VERTICAL

    def __init__(self, context=None, orientation=RecyclerView.VERTICAL, reverse_layout=False):
        if orientation not in (RecyclerView.HORIZONTAL, RecyclerView.VERTICAL):
            raise IllegalArgumentException("invalid orientation: %r" % (orientation,))
        self._orientation = int(orientation)
        self._reverse = bool(reverse_layout)

    def getOrientation(self):
        return self._orientation

    def setOrientation(self, orientation):
        if orientation not in (RecyclerView.HORIZONTAL, RecyclerView.VERTICAL):
            raise IllegalArgumentException("invalid orientation: %r" % (orientation,))
        self._orientation = int(orientation)

    def getReverseLayout(self):
        return self._reverse

    def setReverseLayout(self, value):
        self._reverse = bool(value)


class DefaultItemAnimator(RecyclerView.ItemAnimator):
    pass


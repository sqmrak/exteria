"""NativeByteBuffer, AvatarDrawable, ActionBarPopupWindow, and RecyclerView with its adapter, view holders and linear layout manager"""

import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

from android import _ui  # noqa: E402
from android.app import activity  # noqa: E402
from android.graphics import Bitmap, Canvas  # noqa: E402
from android.view import View  # noqa: E402
from android.widget import FrameLayout, TextView  # noqa: E402
from androidx.recyclerview.widget import DefaultItemAnimator, LinearLayoutManager, RecyclerView  # noqa: E402
from java import jarray, jbyte, jclass  # noqa: E402
from java.lang import (IllegalArgumentException, IllegalStateException, IndexOutOfBoundsException, RuntimeException,  # noqa: E402
                       UnsupportedOperationException)
from org.telegram.tgnet import NativeByteBuffer  # noqa: E402
from org.telegram.ui.ActionBar import ActionBarPopupWindow  # noqa: E402
from org.telegram.ui.Components import AvatarDrawable  # noqa: E402


class Buffer(unittest.TestCase):
    def test_numbers_are_little_endian_and_read_back(self):
        buf = NativeByteBuffer(32)
        buf.writeInt32(-2)
        buf.writeInt64(-(2 ** 40))
        buf.writeDouble(1.5)
        buf.writeByte(0xFF)
        buf.writeBool(True)
        buf.writeBool(False)
        self.assertEqual(buf.position(), 4 + 8 + 8 + 1 + 8)
        buf.rewind()
        self.assertEqual((buf.readInt32(True), buf.readInt64(True), buf.readDouble(True), buf.readByte(True)), (-2, -(2 ** 40), 1.5, -1))
        self.assertEqual((buf.readBool(True), buf.readBool(True)), (True, False))
        buf.rewind()
        self.assertEqual(bytes(buf._data[:4]), struct.pack("<i", -2))

    def test_wrapped_values_are_what_java_would_hold(self):
        buf = NativeByteBuffer(12)
        buf.writeInt32(0xFFFFFFFE)
        buf.writeInt64(2 ** 63)
        buf.rewind()
        self.assertEqual((buf.readInt32(), buf.readInt64()), (-2, -(2 ** 63)))
        self.assertEqual(buf.readUint32(), 0)

    def test_tl_strings_pad_to_four_bytes_and_long_ones_use_three_length_bytes(self):
        buf = NativeByteBuffer(1200)
        buf.writeString("héllo")
        short = buf.position()
        buf.writeByteArray(jarray(jbyte)([1, 2, -3]))
        buf.writeByteArray(bytes(300))
        buf.rewind()
        self.assertEqual(short % 4, 0)
        self.assertEqual(buf.readString(True), "héllo")
        self.assertEqual(buf.readByteArray(True), [1, 2, -3])
        long_array = buf.readByteArray(True)
        self.assertEqual((len(long_array), set(long_array)), (300, {0}))
        self.assertEqual(buf.position() % 4, 0)
        # the array of three bytes took four, so the long one starts at short + 4 with 0xFE and its length in three bytes
        self.assertEqual(bytes(buf._data[short + 4:short + 8]), b"\xfe\x2c\x01\x00")

    def test_a_counting_buffer_only_counts(self):
        count = NativeByteBuffer(True)
        count.writeInt32(1)
        count.writeString("ab")
        count.writeInt64(2)
        self.assertEqual(count.length(), 4 + 4 + 8)

    def test_java_byte_arrays_in_and_out(self):
        buf = NativeByteBuffer(8)
        buf.writeBytes(jarray(jbyte)([-1, 0, 127, -128]))
        buf.writeBytes([1, 2, 3, 4, 5], 1, 2)
        buf.rewind()
        self.assertEqual(buf.readData(4, True), [-1, 0, 127, -128])
        target = [0, 0]
        buf.readBytes(target, True)
        self.assertEqual(target, [2, 3])
        other = NativeByteBuffer(2)
        other.writeBytes(b"\x07\x08")
        wide = NativeByteBuffer(2)
        wide.writeBytes(other.rewind())
        wide.rewind()
        self.assertEqual(wide.readData(2), [7, 8])

    def test_the_cursor_and_the_end(self):
        buf = NativeByteBuffer(16)
        buf.writeInt32(1)
        buf.writeInt32(2)
        buf.flip()
        self.assertEqual((buf.position(), buf.limit(), buf.remaining(), buf.hasRemaining()), (0, 8, 8, True))
        buf.skip(4)
        self.assertEqual(buf.readInt32(), 2)
        self.assertFalse(buf.hasRemaining())
        buf.position(0)
        buf.limit(4)
        self.assertEqual(buf.readInt32(), 1)
        with self.assertRaises(IllegalArgumentException):
            buf.position(5)
        with self.assertRaises(IllegalArgumentException):
            buf.limit(17)
        with self.assertRaises(RuntimeException):
            buf.skip(1)

    def test_compact_moves_the_unread_bytes_to_the_front(self):
        buf = NativeByteBuffer(8)
        buf.writeInt32(1)
        buf.writeInt32(2)
        buf.flip()
        buf.readInt32()
        buf.compact()
        self.assertEqual(buf.position(), 4)
        buf.flip()
        self.assertEqual(buf.readInt32(), 2)

    def test_a_read_past_the_end_follows_the_flag_and_a_write_past_it_raises(self):
        buf = NativeByteBuffer(4)
        buf.writeInt32(9)
        self.assertEqual(buf.readInt32(False), 0)
        self.assertIsNone(buf.readData(1, False))
        self.assertEqual(buf.readString(False), "")
        with self.assertRaises(RuntimeException):
            buf.readInt32(True)
        with self.assertRaises(RuntimeException):
            buf.writeInt32(1)

    def test_a_value_that_is_not_a_bool_is_refused_on_request(self):
        buf = NativeByteBuffer(4)
        buf.writeInt32(5)
        buf.rewind()
        with self.assertRaises(RuntimeException):
            buf.readBool(True)
        buf.rewind()
        self.assertFalse(buf.readBool(False))

    def test_a_given_back_buffer_cannot_be_used_and_the_size_is_bounded(self):
        buf = NativeByteBuffer(4)
        buf.reuse()
        with self.assertRaises(IllegalStateException):
            buf.writeInt32(1)
        with self.assertRaises(IllegalStateException):
            buf.position()
        with self.assertRaises(IllegalArgumentException):
            NativeByteBuffer(-1)
        with self.assertRaises(IllegalArgumentException):
            NativeByteBuffer(NativeByteBuffer.MAX_SIZE + 1)

    def test_what_it_writes_the_serialized_data_of_the_shim_writes_too(self):
        from org.telegram.tgnet import SerializedData
        data = SerializedData()
        data.writeInt32(7)
        data.writeString("x" * 300)
        data.writeInt64(-5)
        raw = data.getBytes()
        buf = NativeByteBuffer(len(raw))
        buf.writeBytes(raw)
        buf.rewind()
        self.assertEqual((buf.readInt32(True), buf.readString(True), buf.readInt64(True)), (7, "x" * 300, -5))
        self.assertFalse(buf.hasRemaining())

    def test_it_resolves_by_its_java_name(self):
        self.assertIs(jclass("org.telegram.tgnet.NativeByteBuffer"), NativeByteBuffer)


class Person:
    def __init__(self, identifier, first, last=""):
        self.id, self.first_name, self.last_name = identifier, first, last


class Chat:
    def __init__(self, identifier, title):
        self.id, self.title = identifier, title


class Avatars(unittest.TestCase):
    def test_the_color_comes_from_the_id_and_the_initials_from_the_names(self):
        avatar = AvatarDrawable()
        avatar.setInfo(Person(3, "anna", "kim"))
        self.assertEqual((avatar.getText(), avatar.getColor()), ("AK", AvatarDrawable.COLORS[3]))
        avatar.setInfo(Person(-10, "Zed"))
        self.assertEqual((avatar.getText(), avatar.getColor()), ("Z", AvatarDrawable.COLORS[10 % 7]))
        avatar.setInfo(Chat(5, "team chat"))
        self.assertEqual((avatar.getText(), avatar.getColor()), ("T", AvatarDrawable.COLORS[5]))
        avatar.setInfo(7, "Ann", "Lee")
        self.assertEqual((avatar.getText(), avatar.getColor()), ("AL", AvatarDrawable.COLORS[0]))
        avatar.setInfo(0, Person(1, "émile", "中"))
        self.assertEqual((avatar.getText(), avatar.getColor()), ("É中", AvatarDrawable.COLORS[1]))
        avatar.setInfo(None)
        self.assertEqual(avatar.getText(), "")

    def test_the_account_argument_form_works(self):
        avatar = AvatarDrawable()
        avatar.setInfo(0, Person(2, "Bo"))
        self.assertEqual(avatar.getColor(), AvatarDrawable.COLORS[2])

    def test_it_draws_a_disc_of_its_color_with_light_letters(self):
        avatar = AvatarDrawable()
        avatar.setInfo(Person(4, "Mia", "Roe"))
        avatar.setBounds(0, 0, 40, 40)
        bitmap = Bitmap(40, 40)
        avatar.draw(Canvas(bitmap))
        self.assertEqual(bitmap.getPixel(20, 2), AvatarDrawable.COLORS[4])
        self.assertEqual(bitmap.getPixel(0, 0), 0)
        self.assertEqual(bitmap.getPixel(39, 39), 0)
        light = sum(1 for x in range(8, 32) for y in range(8, 32) if bitmap.getPixel(x, y) == 0xFFFFFFFF)
        self.assertGreater(light, 0)

    def test_a_person_without_names_is_a_plain_disc_and_the_color_can_be_set(self):
        avatar = AvatarDrawable()
        avatar.setInfo(Person(1, "", ""))
        avatar.setColor(0xFF112233)
        avatar.setBounds(0, 0, 20, 20)
        bitmap = Bitmap(20, 20)
        avatar.draw(Canvas(bitmap))
        self.assertEqual((avatar.getText(), bitmap.getPixel(10, 10)), ("", 0xFF112233))

    def test_it_does_nothing_without_bounds_and_changes_tell_the_view(self):
        avatar = AvatarDrawable()
        bitmap = Bitmap(4, 4)
        avatar.draw(Canvas(bitmap))
        self.assertEqual(bitmap.getPixel(2, 2), 0)
        seen = []
        avatar.setCallback(type("C", (), {"invalidateDrawable": lambda self, who: seen.append(who)})())
        avatar.setInfo(Person(1, "A"))
        avatar.setColor(1)
        self.assertEqual(len(seen), 2)

    def test_it_resolves_by_its_java_name(self):
        self.assertIs(jclass("org.telegram.ui.Components.AvatarDrawable"), AvatarDrawable)


class Popups(unittest.TestCase):
    def setUp(self):
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        _ui.flush()

    def test_the_layout_counts_the_rows_that_are_shown(self):
        layout = ActionBarPopupWindow.ActionBarPopupWindowLayout(self.decor.getContext())
        for index in range(3):
            layout.addView(TextView(self.decor.getContext()))
        layout.getItemAt(1).setVisibility(View.GONE)
        self.assertEqual(layout.getItemsCount(), 2)
        layout.setShownFromBottom(True)
        layout.setFitItems(True)
        self.assertTrue(layout.isShownFromBottom())

    def test_the_window_shows_and_closes_like_a_popup(self):
        layout = ActionBarPopupWindow.ActionBarPopupWindowLayout(self.decor.getContext())
        layout.addView(TextView(self.decor.getContext()))
        popup = ActionBarPopupWindow(layout, -2, -2, True)
        popup.showAtLocation(self.decor, 51, 10, 20)
        self.assertTrue(popup.isShowing())
        popup.startAnimation()
        self.assertTrue(popup.isShowing())
        popup.dismiss(False)
        self.assertFalse(popup.isShowing())
        wrapped = ActionBarPopupWindow(layout, 100, 50)
        self.assertEqual(wrapped.getContentView(), layout)
        self.assertIsNone(ActionBarPopupWindow(self.decor.getContext()).getContentView())

    def test_it_resolves_by_its_java_name(self):
        self.assertIs(jclass("org.telegram.ui.ActionBar.ActionBarPopupWindow"), ActionBarPopupWindow)


class Rows(RecyclerView.Adapter):
    def __init__(self, texts, context):
        super().__init__()
        self.texts = list(texts)
        self.context = context
        self.created = 0
        self.bound = []

    def getItemCount(self):
        return len(self.texts)

    def getItemViewType(self, position):
        return 1 if self.texts[position].startswith("#") else 0

    def onCreateViewHolder(self, parent, view_type):
        self.created += 1
        view = TextView(self.context)
        view.setTextSize(10)
        return RecyclerView.ViewHolder(view)

    def onBindViewHolder(self, holder, position, *payloads):
        self.bound.append(position)
        holder.itemView.setText(self.texts[position])


class Lists(unittest.TestCase):
    def setUp(self):
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        _ui.flush()
        self.context = self.decor.getContext()

    def make(self, texts, orientation=LinearLayoutManager.VERTICAL, reverse=False, size=(200, 100)):
        rv = RecyclerView(self.context)
        adapter = Rows(texts, self.context)
        rv.setLayoutManager(LinearLayoutManager(self.context, orientation, reverse))
        rv.setAdapter(adapter)
        self.decor.addView(rv, FrameLayout.LayoutParams(*size))
        _ui.flush()
        return rv, adapter

    def texts_in_order(self, rv):
        return [str(rv._column.getChildAt(i).getText()) for i in range(rv._column.getChildCount())]

    def test_every_item_gets_a_row_in_order(self):
        rv, adapter = self.make(["a", "b", "c"])
        self.assertEqual(self.texts_in_order(rv), ["a", "b", "c"])
        self.assertEqual(adapter.bound, [0, 1, 2])
        tops = [rv._column.getChildAt(i).getTop() for i in range(3)]
        self.assertEqual(tops, sorted(tops))
        self.assertEqual(len(set(tops)), 3)
        self.assertEqual(rv._column.getChildAt(0).getWidth(), 200)

    def test_the_content_is_taller_than_the_view_so_it_scrolls(self):
        rv, _adapter = self.make(["x"] * 30, size=(200, 60))
        self.assertGreater(rv._column.getHeight(), 60)
        sent = [op[2]["content"] for op in fake.ops if op[0] == "set" and op[1] == rv._id and "content" in op[2]]
        self.assertGreater(sent[-1][1], 60)

    def test_a_row_layout_runs_sideways(self):
        rv, _adapter = self.make(["aaaa", "bbbb", "cccc"] * 8, orientation=LinearLayoutManager.HORIZONTAL, size=(100, 40))
        lefts = [rv._column.getChildAt(i).getLeft() for i in range(3)]
        self.assertEqual(lefts, sorted(lefts))
        self.assertGreater(rv._column.getWidth(), 100)
        self.assertEqual(rv._column.getChildAt(0).getHeight(), 40)

    def test_a_reversed_list_puts_the_first_item_last(self):
        rv, _adapter = self.make(["a", "b", "c"], reverse=True)
        self.assertEqual(self.texts_in_order(rv), ["c", "b", "a"])

    def test_view_types_pick_their_own_holders_and_holders_are_reused(self):
        rv, adapter = self.make(["a", "#h", "b"])
        self.assertEqual(adapter.created, 3)
        holder = rv.findViewHolderForAdapterPosition(1)
        self.assertEqual((holder.getItemViewType(), holder.getAdapterPosition()), (1, 1))
        adapter.texts.append("c")
        adapter.notifyDataSetChanged()
        self.assertEqual(adapter.created, 4)
        self.assertEqual(self.texts_in_order(rv), ["a", "#h", "b", "c"])

    def test_a_changed_item_is_bound_again_and_no_other(self):
        rv, adapter = self.make(["a", "b", "c"])
        adapter.bound.clear()
        adapter.texts[1] = "B"
        adapter.notifyItemChanged(1)
        self.assertEqual(adapter.bound, [1])
        self.assertEqual(self.texts_in_order(rv), ["a", "B", "c"])
        adapter.bound.clear()
        adapter.notifyItemRangeChanged(0, 2)
        self.assertEqual(adapter.bound, [0, 1])
        with self.assertRaises(IndexOutOfBoundsException):
            adapter.notifyItemChanged(9)

    def test_inserting_and_removing_rebuild_the_list(self):
        rv, adapter = self.make(["a", "b"])
        adapter.texts.insert(1, "x")
        adapter.notifyItemInserted(1)
        self.assertEqual(self.texts_in_order(rv), ["a", "x", "b"])
        adapter.texts.pop(0)
        adapter.notifyItemRemoved(0)
        self.assertEqual(self.texts_in_order(rv), ["x", "b"])
        self.assertEqual(adapter.created, 3)

    def test_the_child_position_and_the_holder_are_found(self):
        rv, _adapter = self.make(["a", "b"])
        view = rv._column.getChildAt(1)
        self.assertEqual(rv.getChildAdapterPosition(view), 1)
        self.assertEqual(rv.getChildAdapterPosition(View(self.context)), RecyclerView.NO_POSITION)
        self.assertIsNone(rv.findViewHolderForAdapterPosition(5))

    def test_a_new_adapter_replaces_the_old_one(self):
        rv, old = self.make(["a"])
        new = Rows(["p", "q"], self.context)
        rv.setAdapter(new)
        self.assertEqual(self.texts_in_order(rv), ["p", "q"])
        old.texts.append("z")
        old.notifyDataSetChanged()
        self.assertEqual(self.texts_in_order(rv), ["p", "q"])
        self.assertIs(rv.getAdapter(), new)
        rv.setAdapter(None)
        self.assertEqual(rv._column.getChildCount(), 0)

    def test_a_list_longer_than_the_limit_says_so(self):
        rv, adapter = self.make(["a"])
        adapter.texts = ["a"] * (RecyclerView.MAX_ITEMS + 1)
        with self.assertRaises(IllegalStateException):
            adapter.notifyDataSetChanged()

    def test_a_wrong_holder_and_missing_pieces_are_errors(self):
        class Bad(Rows):
            def onCreateViewHolder(self, parent, view_type):
                return TextView(self.context)

        rv = RecyclerView(self.context)
        rv.setLayoutManager(LinearLayoutManager(self.context))
        with self.assertRaises(IllegalStateException):
            rv.setAdapter(Bad(["a"], self.context))
        with self.assertRaises(IllegalArgumentException):
            RecyclerView.ViewHolder(None)
        with self.assertRaises(NotImplementedError):
            RecyclerView.Adapter().getItemCount()
        with self.assertRaises(IllegalArgumentException):
            LinearLayoutManager(self.context, 7)

    def test_item_views_keep_the_margins_they_were_made_with(self):
        class Margins(Rows):
            def onCreateViewHolder(self, parent, view_type):
                holder = super().onCreateViewHolder(parent, view_type)
                params = FrameLayout.LayoutParams(-1, 30)
                params.setMargins(4, 5, 6, 7)
                holder.itemView.setLayoutParams(params)
                return holder

        rv = RecyclerView(self.context)
        rv.setLayoutManager(LinearLayoutManager(self.context))
        rv.setAdapter(Margins(["a"], self.context))
        self.decor.addView(rv, FrameLayout.LayoutParams(200, 100))
        _ui.flush()
        child = rv._column.getChildAt(0)
        self.assertEqual((child.getLeft(), child.getTop(), child.getHeight()), (4, 5, 30))

    def test_scrolling_is_the_apps_and_a_plugin_is_told_so(self):
        rv, _adapter = self.make(["a"])
        for call in (lambda: rv.addOnScrollListener(object()), lambda: rv.scrollToPosition(0), lambda: rv.smoothScrollToPosition(0)):
            with self.assertRaises(UnsupportedOperationException):
                call()

    def test_the_item_animator_keeps_its_settings(self):
        animator = DefaultItemAnimator()
        animator.setSupportsChangeAnimations(False)
        animator.setAddDuration(5)
        self.assertEqual((animator.getSupportsChangeAnimations(), animator.getAddDuration(), animator.getMoveDuration()), (False, 5, 250))
        rv = RecyclerView(self.context)
        rv.setItemAnimator(animator)
        self.assertIs(rv.getItemAnimator(), animator)

    def test_the_classes_resolve_by_their_java_names(self):
        self.assertIs(jclass("androidx.recyclerview.widget.LinearLayoutManager"), LinearLayoutManager)
        self.assertIs(jclass("androidx.recyclerview.widget.RecyclerView"), RecyclerView)
        self.assertIs(jclass("androidx.recyclerview.widget.DefaultItemAnimator"), DefaultItemAnimator)
        self.assertIs(jclass("androidx.recyclerview.widget.RecyclerView$Adapter"), RecyclerView.Adapter)
        self.assertIs(jclass("androidx.recyclerview.widget.RecyclerView$ViewHolder"), RecyclerView.ViewHolder)


if __name__ == "__main__":
    unittest.main()

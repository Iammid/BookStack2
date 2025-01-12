<nav id="book-tree" class="book-tree mb-xl" aria-label="{{ trans('entities.books_navigation') }}">
    <h5>{{ trans('entities.books_navigation') }}</h5>

    <ul class="sidebar-page-list mt-xs menu entity-list">
        @if (userCan('view', $book))
            <li class="list-item-book book">
                @include('entities.list-item-basic', ['entity' => $book, 'classes' => ($current->matches($book) ? 'selected' : '')])
            </li>
        @endif

        {{-- Render the first level of chapters and pages --}}
        @foreach($sidebarTree as $bookChild)
            @include('entities.book-tree-branch', ['bookChild' => $bookChild, 'current' => $current])
        @endforeach
    </ul>
</nav>

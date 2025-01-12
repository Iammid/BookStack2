@php
    $isOpen = $isOpen ?? false;
@endphp

<li class="list-item-{{ $bookChild->getType() }} {{ $bookChild->getType() }} {{ $bookChild->isA('page') && $bookChild->draft ? 'draft' : '' }}">
    @include('entities.list-item-basic', ['entity' => $bookChild, 'classes' => ($current->matches($bookChild) ? 'selected' : '')])

    @if($bookChild->isA('chapter') && ($bookChild->childChapters->count() > 0 || $bookChild->pages->count() > 0))
        @php
            // Determine if this branch should be open
            $isOpen = $bookChild->matchesOrContains($current);
        @endphp
        <div class="entity-list-item no-hover">
            <span class="icon text-chapter">@icon('chapter')</span>
            <div class="content">
                <ul refs="content" 
                    class="nested-chapter-list {{ $isOpen ? 'open' : 'hidden' }}">
                    @foreach($bookChild->childChapters as $childChapter)
                    @include('entities.book-tree-branch', [
    'bookChild' => $childChapter,
    'current'   => $current,
    'isOpen'    => false,
])
                    @endforeach
                    {{-- Include pages within the chapter --}}
                    @if($bookChild->pages && $bookChild->pages->count() > 0)
                        @foreach($bookChild->pages as $page)
                            <li class="list-item-page {{ $page->isA('page') && $page->draft ? 'draft' : '' }}" role="presentation">
                                @include('entities.list-item-basic', ['entity' => $page, 'classes' => ($current->matches($page) ? 'selected' : '')])
                            </li>
                        @endforeach
                    @endif
                </ul>
            </div>
        </div>
    @endif
</li>

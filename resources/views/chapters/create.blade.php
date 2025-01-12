@extends('layouts.simple')

@section('body')
<div class="container small">
    <div class="my-s">

    </div>

    <main class="content-wrap card">
        <h1 class="list-heading">{{ trans('entities.chapters_create') }}</h1>

        {{-- Form action URL is different depending on whether it's a top-level chapter or a subchapter --}}
        <form action="{{ $parentChapter ? $parentChapter->getUrl('/create-chapter') : $book->getUrl('/create-chapter') }}" method="POST">
            @csrf
            @include('chapters.parts.form')  {{-- Reuse form partial --}}
        </form>
    </main>
</div>
@stop

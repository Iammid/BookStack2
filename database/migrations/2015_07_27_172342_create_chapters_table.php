<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('chapters', function (Blueprint $table) {
            $table->increments('id');
            $table->integer('book_id')->unsigned();
            $table->integer('parent_chapter_id')->nullable()->unsigned();
            $table->string('slug')->indexed();
            $table->text('name');
            $table->text('description')->nullable();
            $table->integer('priority')->default(0);
            $table->timestamps();
        
            $table->foreign('book_id')->references('id')->on('books')->onDelete('cascade');
            $table->foreign('parent_chapter_id')->references('id')->on('chapters')->onDelete('cascade');
        });        
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::drop('chapters');
    }
};

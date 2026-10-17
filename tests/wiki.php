<?php
/** Integration runner: NEVER run on a production wiki. Overwrites named test modules/pages. */
require_once ( getenv( 'MW_INSTALL_PATH' ) ?: dirname( __DIR__, 3 ) ) . '/maintenance/Maintenance.php';
class ChartsIntegrationTest extends Maintenance {
    public function __construct() {
        parent::__construct();
        $this->addOption( 'disposable-wiki', 'Allow overwriting Module:Charts, ChartsTests, ChartData and Charts demo', false, false );
    }
    public function execute() {
        if ( !$this->hasOption( 'disposable-wiki' ) ) {
            $this->fatalError( 'Use --disposable-wiki on a test wiki only.' );
        }
        $services = MediaWiki\MediaWikiServices::getInstance();
        $user = $services->getUserFactory()->newFromName( 'Admin' );
        RequestContext::getMain()->setUser( $user );
        $files = [ 'Module:Charts' => 'Charts.lua', 'Module:ChartsTests' => 'tests/ChartsTests.lua',
            'Module:ChartData' => 'examples/ChartData.lua', 'Charts demo' => 'examples/Gallery.wikitext',
            'Charts advanced' => 'examples/Advanced.wikitext', 'Charts leaderboard' => 'examples/Leaderboard.wikitext' ];
        foreach ( $files as $name => $file ) {
            $title = MediaWiki\Title\Title::newFromText( $name );
            $page = $services->getWikiPageFactory()->newFromTitle( $title );
            $content = ContentHandler::makeContent( file_get_contents( __DIR__ . '/../' . $file ), $title,
                str_starts_with( $name, 'Module:' ) ? 'Scribunto' : CONTENT_MODEL_WIKITEXT );
            $status = $page->doUserEditContent( $content, $user, 'ScribuntoCharts test fixture' );
            if ( !$status->isOK() ) {
                $this->fatalError( 'Cannot save ' . $name );
            }
            DeferredUpdates::doUpdates();
        }
        $parse = static function ( $text ) use ( $services ) {
            $options = ParserOptions::newFromAnon();
            $output = $services->getParserFactory()->create()->parse( $text,
                MediaWiki\Title\Title::newFromText( 'Charts demo' ), $options );
            return $output->runOutputPipeline( $options )->getContentHolderText();
        };
        $result = $parse( '{{#invoke:ChartsTests|run}}' );
        if ( !preg_match( '/PASS: \d+ chart assertions/', $result, $match ) ) {
            $this->fatalError( $result );
        }
        $this->output( $match[0] . "\n" );
        $gallery = $parse( file_get_contents( __DIR__ . '/../examples/Gallery.wikitext' ) );
        foreach ( [ 'conic-gradient(', 'rotate(129.600000deg)', 'sc-data', 'sc-progress', 'sc-stacked', 'scope="row"' ] as $needle ) {
            if ( strpos( $gallery, $needle ) === false ) {
                $this->fatalError( 'Parser stripped or lost: ' . $needle );
            }
        }
        foreach ( [ 'scribunto-error', 'scribunto-chart-error', 'insecure input', '<script', '&lt;thead', '&lt;tbody' ] as $needle ) {
            if ( strpos( $gallery, $needle ) !== false ) {
                $this->fatalError( 'Unexpected gallery output: ' . $needle );
            }
        }
        $example = $parse( '{{#invoke:ChartData|budget}}' );
        if ( strpos( $example, 'Development' ) === false || strpos( $example, 'scribunto-error' ) !== false ) {
            $this->fatalError( 'Lua caller example failed' );
        }
        $escaped = $parse( '{{#invoke:Charts|donut|value1=1|label1=<img src=x onerror=alert(1)>}}' );
        if ( strpos( $escaped, '<img' ) !== false || strpos( $escaped, 'scribunto-error' ) !== false ) {
            $this->fatalError( 'Literal label handling failed' );
        }
        $this->output( "PASS: real parser CSS, accessibility markup, gallery and Lua caller\n" );
        $advanced = $parse( file_get_contents( __DIR__ . '/../examples/Advanced.wikitext' ) );
        foreach ( [ 'sc-columns', 'sc-matrix', 'sc-heat-cell', 'sc-task-bar', 'sc-target', 'linear-gradient(' ] as $needle ) {
            if ( strpos( $advanced, $needle ) === false ) { $this->fatalError( 'Advanced parser lost: ' . $needle ); }
        }
        if ( strpos( $advanced, 'scribunto-error' ) !== false || strpos( $advanced, 'scribunto-chart-error' ) !== false ) {
            $this->fatalError( $advanced );
        }
        $services->getWikiPageFactory()->newFromTitle( MediaWiki\Title\Title::newFromText( 'Charts advanced' ) )->doPurge();
        $this->output( "PASS: advanced chart parser output\n" );
        $ranking = $parse( file_get_contents( __DIR__ . '/../examples/Leaderboard.wikitext' ) );
        if ( strpos( $ranking, 'scribunto-error' ) !== false || strpos( $ranking, 'scribunto-chart-error' ) !== false || substr_count( $ranking, 'class="sc-trophy"' ) !== 3 ) {
            $this->fatalError( 'Leaderboard parser check failed: ' . $ranking );
        }
        $services->getWikiPageFactory()->newFromTitle( MediaWiki\Title\Title::newFromText( 'Charts leaderboard' ) )->doPurge();
        $this->output( "PASS: leaderboard parser output and trophies\n" );
        $services->getWikiPageFactory()->newFromTitle(
            MediaWiki\Title\Title::newFromText( 'Charts demo' )
        )->doPurge();
        DeferredUpdates::doUpdates();
    }
}
$maintClass = ChartsIntegrationTest::class;
require_once RUN_MAINTENANCE_IF_MAIN;

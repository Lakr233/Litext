//
//  ViewController.m
//  LitextSamples
//
//  Created by Cyandev on 2022/5/8.
//

#import <Litext/Litext.h>

#import "ViewController.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet LTXLabel *label;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *trailingConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *heightConstraint;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] init];
    [attributedString appendAttributedString:[[NSAttributedString alloc]
                                              initWithString:@"Lorem ipsum"
                                              attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:18 weight:UIFontWeightBold]
    }]];
    [attributedString appendAttributedString:[[NSAttributedString alloc]
                                              initWithString:@" dolor sit amet, consectetur adipiscing elit. "
                                              attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:14]
    }]];
    [attributedString appendAttributedString:[[NSAttributedString alloc]
                                              initWithString:@"Proin eu aliquet orci."
                                              attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:14],
        NSLinkAttributeName: @"https://www.lipsum.com/",
        NSForegroundColorAttributeName: (id) [UIColor linkColor].CGColor,
    }]];
    [attributedString appendAttributedString:[[NSAttributedString alloc]
                                              initWithString:@" 中文测试，那只敏捷的棕毛狐狸🦊跳上了那只懒狗🐶。"
                                              attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:14]
    }]];
    LTXAttachment *attachment = [[LTXAttachment alloc] init];
    attachment.view = [[UISwitch alloc] init];
    attachment.size = attachment.view.intrinsicContentSize;
    [attributedString appendAttributedString:[[NSAttributedString alloc]
                                              initWithString:@"\uFFFC"
                                              attributes:@{
        LTXAttachmentAttributeName: attachment,
        (id) kCTRunDelegateAttributeName: attachment.runDelegate,
    }]];
    [attributedString appendAttributedString:[[NSAttributedString alloc]
                                              initWithString:@" Sed quis pretium ligula. Duis dictum faucibus turpis,"
                                                             @" et sagittis dolor. Ut dapibus fermentum sollicitudin."
                                                             @" Nulla commodo pulvinar lobortis. Nunc vel justo ornare"
                                                             @" nisi pulvinar rhoncus. Duis ornare gravida mauris, sed"
                                                             @" scelerisque nibh dapibus id.\nNew line test."
                                              attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:16],
        NSForegroundColorAttributeName: (id) [UIColor systemOrangeColor].CGColor,
    }]];
    
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.lineSpacing = 4;
    [attributedString addAttributes:@{
        NSParagraphStyleAttributeName: paragraphStyle,
    } range:NSMakeRange(0, attributedString.length)];
    
    self.label.attributedText = attributedString;
}

- (IBAction)handleTrailingPaddingChange:(id)sender {
    self.trailingConstraint.constant = ((UISlider *) sender).value;
}

- (IBAction)handleHeightLimitChange:(id)sender {
    self.heightConstraint.constant = ((UISwitch *) sender).isOn ? 64 : 1000;
}

@end
